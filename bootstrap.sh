#!/usr/bin/env bash
set -euo pipefail

# Ensure we're inside a WP install
wp core is-installed >/dev/null 2>&1 || { echo "WordPress not detected"; exit 1; }

echo "== wp-config constants =="
wp config set WP_ENVIRONMENT_TYPE development --type=constant --raw 2>/dev/null || true
wp config set WP_DEBUG             true        --type=constant --raw 2>/dev/null || true
wp config set WP_DEBUG_LOG         true        --type=constant --raw 2>/dev/null || true
wp config set WP_DEBUG_DISPLAY     false       --type=constant --raw 2>/dev/null || true
wp config set SCRIPT_DEBUG         true        --type=constant --raw 2>/dev/null || true
wp config set DISALLOW_FILE_EDIT   true        --type=constant --raw 2>/dev/null || true
wp config set WP_MEMORY_LIMIT      256M        --type=constant --raw 2>/dev/null || true
wp config set WP_DISABLE_FATAL_ERROR_HANDLER true --type=constant --raw 2>/dev/null || true
wp config set WP_POST_REVISIONS    10          --type=constant --raw 2>/dev/null || true

echo "== Core options =="
wp option update timezone_string 'Europe/London'
wp rewrite structure '/%postname%/' --hard

# Random tagline
TAGLINE="$(LC_ALL=C tr -dc 'a-z' </dev/urandom 2>/dev/null | head -c 8 || echo 'Just another site')"
wp option update blogdescription "$TAGLINE"

wp option update date_format 'j F Y'
wp option update time_format 'H:i'
wp option update blog_public 0   # discourage search engines

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

echo "== Content: delete defaults =="
HW_ID="$(wp post list --post_type=post --title='Hello world!' --format=ids)"
[ -n "$HW_ID" ] && wp post delete "$HW_ID" --force || true
SP_ID="$(wp post list --post_type=page --title='Sample Page' --format=ids)"
[ -n "$SP_ID" ] && wp post delete "$SP_ID" --force || true

echo "== Plugins =="
wp plugin delete akismet hello 2>/dev/null || true
wp plugin install gutenberg query-monitor debug-bar user-switching regenerate-thumbnails wp-mail-logging --activate || true

echo "== Themes =="
wp theme activate twentytwentyfive || true
wp theme delete twentytwentyfour twentytwentythree 2>/dev/null || true

echo "== Discussion & pingbacks =="
wp option update comments_notify 0
wp option update moderation_notify 0
wp option update default_ping_status 'closed'
wp option update comment_moderation 1
wp option update comment_previously_approved 0

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

echo "== Menus =="
if ! wp menu list --fields=slug | grep -q '^main-menu$'; then
	wp menu create "Main Menu" >/dev/null
fi
wp menu item add-post main-menu "$HOME_ID" >/dev/null 2>&1 || true
wp menu item add-post main-menu "$BLOG_ID" >/dev/null 2>&1 || true
wp menu location assign main-menu primary 2>/dev/null || true

echo "== Widgets / sidebars =="
wp option update sidebars_widgets "{\"time\": $(date +%s), \"wp_inactive_widgets\": []}" --format=json 2>/dev/null || true

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

echo "== Finalize =="
wp rewrite flush --hard
echo -e "\nBootstrap complete."
