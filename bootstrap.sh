#!/usr/bin/env bash
set -euo pipefail

# --- Self-heal & sanity checks -------------------------------------------------
# Must be in the WP site root
[ -f wp-config.php ] || { echo "wp-config.php not found in: $PWD"; exit 1; }

# If wp-config.php has a parse error (often unquoted 256M/512M or environment type), try to auto-fix, then re-check
if ! php -l wp-config.php >/dev/null 2>&1; then
	echo "wp-config.php has a PHP syntax error; attempting auto-fix for common issues…"
	BACKUP="wp-config.php.bak.$(date +%s)"
	cp wp-config.php "$BACKUP"
	echo "Backup created: $BACKUP"

	# Quote bare M/G values for memory constants (covers ' or " names, and bare names)
	perl -i -pe "s/define\(\s*(['\"])WP_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT', '\$2\$3')/ig" wp-config.php
	perl -i -pe "s/define\(\s*(['\"])WP_MAX_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT', '\$2\$3')/ig" wp-config.php
	perl -i -pe "s/define\(\s*WP_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT', '\$1\$2')/ig" wp-config.php
	perl -i -pe "s/define\(\s*WP_MAX_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT', '\$1\$2')/ig" wp-config.php

	# Quote unquoted WP_ENVIRONMENT_TYPE values (development|staging|production)
	perl -i -pe "s/define\(\s*(['\"])WP_ENVIRONMENT_TYPE\1\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE', '\$2')/i" wp-config.php
	perl -i -pe "s/define\(\s*WP_ENVIRONMENT_TYPE\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE', '\$1')/i" wp-config.php

	php -l wp-config.php >/dev/null || { echo "Still seeing a syntax error in wp-config.php. Open it and fix the reported line."; exit 1; }
fi

# Confirm WP loads (no plugins/themes) so WP-CLI can proceed
wp core is-installed --skip-plugins --skip-themes >/dev/null 2>&1 \
	|| { echo "WP-CLI can't load WordPress here (check path/config)."; exit 1; }

# --- wp-config.php constants ---------------------------------------------------
echo "== wp-config constants =="
# Strings -> let WP-CLI quote them (no --raw)
wp config set WP_ENVIRONMENT_TYPE development --type=constant        2>/dev/null || true
wp config set WP_MEMORY_LIMIT      256M        --type=constant        2>/dev/null || true
# Booleans / ints -> keep --raw
wp config set WP_DEBUG             true        --type=constant --raw  2>/dev/null || true
wp config set WP_DEBUG_LOG         true        --type=constant --raw  2>/dev/null || true
wp config set WP_DEBUG_DISPLAY     false       --type=constant --raw  2>/dev/null || true
wp config set SCRIPT_DEBUG         true        --type=constant --raw  2>/dev/null || true
wp config set DISALLOW_FILE_EDIT   true        --type=constant --raw  2>/dev/null || true
wp config set WP_DISABLE_FATAL_ERROR_HANDLER true --type=constant --raw 2>/dev/null || true
wp config set WP_POST_REVISIONS    10            --type=constant --raw 2>/dev/null || true

# --- Core options --------------------------------------------------------------
echo "== Core options =="
wp option update timezone_string 'Europe/London'
wp rewrite structure '/%postname%/' --hard

# Random tagline (lowercase 8 chars); change to a fixed string if you prefer
TAGLINE="$(LC_ALL=C tr -dc 'a-z' </dev/urandom 2>/dev/null | head -c 8 || echo 'Just another site')"
wp option update blogdescription "$TAGLINE"

wp option update date_format 'j F Y'
wp option update time_format 'H:i'
wp option update blog_public 0   # discourage search engines

# --- Pages (Home/Blog) ---------------------------------------------------------
echo "== Content: pages =="
ensure_page () { # title slug -> id
	local ID
	ID="$(wp post list --post_type=page --pagename="$2" --format=ids)"
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

# --- Delete defaults -----------------------------------------------------------
echo "== Content: delete defaults =="
HW_ID="$(wp post list --post_type=post --title='Hello world!' --format=ids)"
[ -n "$HW_ID" ] && wp post delete "$HW_ID" --force || true
SP_ID="$(wp post list --post_type=page --title='Sample Page' --format=ids)"
[ -n "$SP_ID" ] && wp post delete "$SP_ID" --force || true

# --- Plugins -------------------------------------------------------------------
echo "== Plugins =="
wp plugin delete akismet hello 2>/dev/null || true
wp plugin install gutenberg query-monitor debug-bar user-switching regenerate-thumbnails wp-mail-logging --activate || true

# --- Themes --------------------------------------------------------------------
echo "== Themes =="
wp theme activate twentytwentyfive || true
wp theme delete twentytwentyfour twentytwentythree 2>/dev/null || true

# --- Discussion settings -------------------------------------------------------
echo "== Discussion & pingbacks =="
wp option update comments_notify 0
wp option update moderation_notify 0
wp option update default_ping_status 'closed'
wp option update comment_moderation 1
wp option update comment_previously_approved 0

# --- Media defaults ------------------------------------------------------------
echo "== Media defaults =="
wp option update thumbnail_size_w 150
wp option update thumbnail_size_h 150
wp option update medium_size_w 1024
wp option update medium_size_h 1024
wp option update large_size_w 2048
wp option update large_size_h 2048
wp option update medium_large_size_w 1536
wp option update medium_large_size_h 1536
wp option update image_default_size 'large'

# --- Menus ---------------------------------------------------------------------
echo "== Menus =="
if ! wp menu list --fields=slug | grep -q '^main-menu$'; then
	wp menu create "Main Menu" >/dev/null
fi
wp menu item add-post main-menu "$HOME_ID" >/dev/null 2>&1 || true
wp menu item add-post main-menu "$BLOG_ID" >/dev/null 2>&1 || true
wp menu location assign main-menu primary 2>/dev/null || true

# --- Widgets / sidebars --------------------------------------------------------
echo "== Widgets / sidebars =="
wp option update sidebars_widgets "{\"time\": $(date +%s), \"wp_inactive_widgets\": []}" --format=json 2>/dev/null || true

# --- Emoji & oEmbed cleanup (MU-plugin) ---------------------------------------
echo "== Emoji & oEmbed cleanup (MU-plugin) =="
MU_DIR="wp-content/mu-plugins"
mkdir -p "$MU_DIR"
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

# --- Finish --------------------------------------------------------------------
echo "== Finalize =="
wp rewrite flush --hard
echo -e "\nBootstrap complete."
