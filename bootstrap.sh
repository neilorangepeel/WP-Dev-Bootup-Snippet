#!/usr/bin/env bash
set -euo pipefail

# ── Self‑heal & sanity checks (wp-config) ─────────────────────────────────
# Ensure we’re in the site root
[ -f wp-config.php ] || { echo "wp-config.php not found in: $PWD"; exit 1; }

# If wp-config.php has a parse error (e.g., unquoted 256M or env type), auto‑fix
if ! php -l wp-config.php >/dev/null 2>&1; then
  echo "wp-config.php has a PHP syntax error; attempting auto-fix…"
  BACKUP="wp-config.php.bak.$(date +%s)"; cp wp-config.php "$BACKUP"; echo "Backup: $BACKUP"
  # Quote bare memory values like 256M → '256M'
  perl -i -pe "s/define\(\s*(['\"])WP_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT','\$2\$3')/ig" wp-config.php
  perl -i -pe "s/define\(\s*(['\"])WP_MAX_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT','\$2\$3')/ig" wp-config.php
  perl -i -pe "s/define\(\s*WP_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT','\$1\$2')/ig" wp-config.php
  perl -i -pe "s/define\(\s*WP_MAX_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT','\$1\$2')/ig" wp-config.php
  # Quote unquoted environment type values
  perl -i -pe "s/define\(\s*(['\"])WP_ENVIRONMENT_TYPE\1\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE','\$2')/i" wp-config.php
  perl -i -pe "s/define\(\s*WP_ENVIRONMENT_TYPE\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE','\$1')/i" wp-config.php
  php -l wp-config.php >/dev/null || { echo "Still seeing a syntax error; fix the reported line."; exit 1; }
fi

# Confirm WordPress loads (no plugins/themes)
wp core is-installed --skip-plugins --skip-themes >/dev/null 2>&1 \
  || { echo "WP-CLI can't load WordPress here (check path/config)."; exit 1; }

# ── wp-config.php constants ───────────────────────────────────────────────
echo "== wp-config constants =="
# Strings → let WP‑CLI quote them
wp config set WP_ENVIRONMENT_TYPE development --type=constant        2>/dev/null || true
wp config set WP_MEMORY_LIMIT      256M        --type=constant        2>/dev/null || true
# Booleans/ints → raw
wp config set WP_DEBUG true        --type=constant --raw 2>/dev/null || true
wp config set WP_DEBUG_LOG true    --type=constant --raw 2>/dev/null || true
wp config set WP_DEBUG_DISPLAY false --type=constant --raw 2>/dev/null || true
wp config set SCRIPT_DEBUG true    --type=constant --raw 2>/dev/null || true
wp config set DISALLOW_FILE_EDIT true --type=constant --raw 2>/dev/null || true
wp config set WP_DISABLE_FATAL_ERROR_HANDLER true --type=constant --raw 2>/dev/null || true
wp config set WP_POST_REVISIONS 10 --type=constant --raw 2>/dev/null || true

# ── Core options ─────────────────────────────────────────────────────────
echo "== Core options =="
wp option update timezone_string 'Europe/London'
wp rewrite structure '/%postname%/'      # no --hard in Studio/nginx
wp option update blogdescription "Just another site"
wp option update date_format 'j F Y'
wp option update time_format 'H:i'
wp option update blog_public 0           # discourage indexing

# ── Pages (Home/Blog) ────────────────────────────────────────────────────
echo "== Content: pages =="
ensure_page () { # usage: ensure_page "Title" slug → prints ID
  local ID; ID="$(wp post list --post_type=page --pagename="$2" --format=ids)"
  if [ -z "$ID" ]; then
    ID="$(wp post create --post_type=page --post_status=publish --post_title="$1" --post_name="$2" --porcelain)"
  fi
  echo "$ID"
}
HOME_ID="$(ensure_page 'Home' 'home')"
BLOG_ID="$(ensure_page 'Blog' 'blog')"
wp option update show_on_front 'page'
wp option update page_on_front "$HOME_ID"
wp option update page_for_posts "$BLOG_ID"

# ── Delete defaults ──────────────────────────────────────────────────────
echo "== Content: delete defaults =="
HW_ID="$(wp post list --post_type=post --title='Hello world!' --format=ids)" ; [ -n "$HW_ID" ] && wp post delete "$HW_ID" --force || true
SP_ID="$(wp post list --post_type=page --title='Sample Page' --format=ids)" ; [ -n "$SP_ID" ] && wp post delete "$SP_ID" --force || true

# ── Plugins ──────────────────────────────────────────────────────────────
echo "== Plugins =="
wp plugin delete akismet hello 2>/dev/null || true
wp plugin install gutenberg query-monitor debug-bar user-switching regenerate-thumbnails wp-mail-logging --activate || true

# ── Themes ───────────────────────────────────────────────────────────────
echo "== Themes =="
wp theme activate twentytwentyfive || true
wp theme delete twentytwentyfour twentytwentythree 2>/dev/null || true

# ── Discussion settings ──────────────────────────────────────────────────
echo "== Discussion & pingbacks =="
wp option update comments_notify 0
wp option update moderation_notify 0
wp option update default_ping_status 'closed'
wp option update comment_moderation 1
wp option update comment_previously_approved 0

# ── Media defaults (block‑theme friendly) ────────────────────────────────
echo "== Media defaults =="
# Thumbnail: square grids/cards
wp option update thumbnail_size_w 320
wp option update thumbnail_size_h 320
wp option update thumbnail_crop 1
# Medium/Large: width‑only (height 0 keeps aspect)
wp option update medium_size_w 900 ; wp option update medium_size_h 0
wp option update medium_large_size_w 1536 ; wp option update medium_large_size_h 0
wp option update large_size_w 1400 ; wp option update large_size_h 0
wp option update image_default_size 'large'

# ── Navigation (block) ───────────────────────────────────────────────────
echo "== Navigation (block) =="
# Create/reuse a Navigation entity and add Home/Blog links
NAV_ID="$(wp post list --post_type=wp_navigation --title='Main Navigation' --format=ids | head -n1)"
if [ -z "$NAV_ID" ]; then
  NAV_ID="$(wp post create --post_type=wp_navigation --post_status=publish --post_title='Main Navigation' --porcelain)"
fi
TMPNAV="$(mktemp)"
cat > "$TMPNAV" <<EOF
<!-- wp:navigation-link {"label":"Home","type":"page","id":$HOME_ID,"kind":"post-type"} /-->
<!-- wp:navigation-link {"label":"Blog","type":"page","id":$BLOG_ID,"kind":"post-type"} /-->
EOF
wp post update "$NAV_ID" --post_content="$(cat "$TMPNAV")" >/dev/null ; rm -f "$TMPNAV"
echo "Navigation entity ID: $NAV_ID (assign in Site Editor → Header → Navigation)."

# Best‑effort: link nav to header if a navigation block exists without a ref
HEADER_ID="$(wp post list --post_type=wp_template_part --name=header --format=ids | head -n1 || true)"
if [ -n "${HEADER_ID:-}" ]; then
  CONTENT="$(wp post get "$HEADER_ID" --field=post_content)"
  if echo "$CONTENT" | grep -q "<!-- wp:navigation" && ! echo "$CONTENT" | grep -q "\"ref\":"; then
    NEWCONTENT="$(echo "$CONTENT" | perl -0777 -pe "s/(<!--\s*wp:navigation\s*\{)/\${1}\"ref\": $NAV_ID, /")"
    [ -n "$NEWCONTENT" ] && wp post update "$HEADER_ID" --post_content="$NEWCONTENT" >/dev/null && echo "Linked Navigation to header."
  fi
fi

# ── Admin color scheme ───────────────────────────────────────────────────
echo "== Admin color scheme =="
for USER_ID in $(wp user list --field=ID); do
  wp user meta update "$USER_ID" admin_color modern >/dev/null || true
done
echo "Set admin color scheme to: modern"

# ── MU‑plugin: emoji & oEmbed cleanup ────────────────────────────────────
echo "== Emoji & oEmbed cleanup (MU-plugin) =="
MU_DIR="wp-content/mu-plugins" ; mkdir -p "$MU_DIR"
cat > "$MU_DIR/dev-tweaks.php" <<'PHP'
<?php
/*
Plugin Name: Dev Tweaks (disable emojis & oEmbed)
Description: Small front-end cleanups for dev/staging.
*/
add_action('init', function () {
  // Emojis
  remove_action('wp_head', 'print_emoji_detection_script', 7);
  remove_action('admin_print_scripts', 'print_emoji_detection_script');
  remove_action('wp_print_styles', 'print_emoji_styles');
  remove_action('admin_print_styles', 'print_emoji_styles');
  remove_filter('the_content_feed', 'wp_staticize_emoji');
  remove_filter('comment_text_rss', 'wp_staticize_emoji');
  remove_filter('wp_mail', 'wp_staticize_emoji_for_email');
  // oEmbed
  remove_action('wp_head', 'wp_oembed_add_discovery_links');
  remove_action('wp_head', 'wp_oembed_add_host_js');
  remove_filter('oembed_dataparse', 'wp_filter_oembed_result', 10);
  add_filter('embed_oembed_discover', '__return_false');
});
PHP

# ── Finish ───────────────────────────────────────────────────────────────
echo "== Finalize =="
wp rewrite flush

echo -e "\nBootstrap complete."
