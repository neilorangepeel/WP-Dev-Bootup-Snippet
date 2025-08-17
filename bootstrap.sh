#!/usr/bin/env bash
set -euo pipefail

START_TIME=$(date +%s)

# ── Sanity: must be in WP site root
[ -f wp-config.php ] || { echo "wp-config.php not found in $PWD"; exit 1; }

# ── Self-heal common wp-config mistakes (unquoted 256M / env type), then re-lint
if ! php -l wp-config.php >/dev/null 2>&1; then
	echo "Fixing wp-config.php syntax…"
	cp wp-config.php "wp-config.php.bak.$(date +%s)"

	# Quote bare memory values like 256M or 512M
	perl -i -pe "s/define\(\s*([''])WP_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT','\$2\$3')/ig" wp-config.php
	perl -i -pe "s/define\(\s*([''])WP_MAX_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT','\$2\$3')/ig" wp-config.php
	perl -i -pe "s/define\(\s*WP_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT','\$1\$2')/ig" wp-config.php
	perl -i -pe "s/define\(\s*WP_MAX_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT','\$1\$2')/ig" wp-config.php

	# Quote unquoted environment type values
	perl -i -pe "s/define\(\s*([''])WP_ENVIRONMENT_TYPE\1\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE','\$2')/i" wp-config.php
	perl -i -pe "s/define\(\s*WP_ENVIRONMENT_TYPE\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE','\$1')/i" wp-config.php

	php -l wp-config.php >/dev/null || { echo "wp-config.php still has a syntax error (see php -l)."; exit 1; }
fi

# ── Confirm WordPress loads (without plugins/themes)
wp core is-installed --skip-plugins --skip-themes >/dev/null 2>&1 || { echo "WP-CLI can't load WordPress (check path/db)."; exit 1; }

echo "== wp-config constants =="
# String constants (let WP-CLI add quotes)
wp config set WP_ENVIRONMENT_TYPE development --type=constant 2>/dev/null || true
wp config set WP_MEMORY_LIMIT 256M --type=constant 2>/dev/null || true
# Booleans / ints (raw)
wp config set WP_DEBUG true --type=constant --raw 2>/dev/null || true
wp config set WP_DEBUG_LOG true --type=constant --raw 2>/dev/null || true
wp config set WP_DEBUG_DISPLAY false --type=constant --raw 2>/dev/null || true
wp config set SCRIPT_DEBUG true --type=constant --raw 2>/dev/null || true
wp config set DISALLOW_FILE_EDIT true --type=constant --raw 2>/dev/null || true
wp config set WP_DISABLE_FATAL_ERROR_HANDLER true --type=constant --raw 2>/dev/null || true
wp config set WP_POST_REVISIONS 10 --type=constant --raw 2>/dev/null || true

echo "== Core options =="
wp option update timezone_string 'Europe/London'
wp rewrite structure '/%postname%/'             # no --hard (Studio/nginx)
wp option update blogdescription 'Just another site'
wp option update date_format 'j F Y'
wp option update time_format 'H:i'
wp option update blog_public 0                  # discourage indexing

# Helper: create page if missing, return ID
ensure_page () {
	local TITLE="$1" SLUG="$2" ID
	ID="$(wp post list --post_type=page --pagename="$SLUG" --format=ids)"
	[ -n "$ID" ] || ID="$(wp post create --post_type=page --post_status=publish --post_title="$TITLE" --post_name="$SLUG" --porcelain)"
	echo "$ID"
}

echo "== Content: pages =="
HOME_ID="$(ensure_page 'Home' 'home')"
ABOUT_ID="$(ensure_page 'About' 'about')"
BLOG_ID="$(ensure_page 'Blog' 'blog')"
CONTACT_ID="$(ensure_page 'Contact' 'contact')"
wp option update show_on_front 'page'
wp option update page_on_front "$HOME_ID"
wp option update page_for_posts "$BLOG_ID"

echo "== Content: delete defaults =="
HW_ID="$(wp post list --post_type=post --title='Hello world!' --format=ids)"; [ -z "$HW_ID" ] || wp post delete "$HW_ID" --force
SP_ID="$(wp post list --post_type=page --title='Sample Page' --format=ids)"; [ -z "$SP_ID" ] || wp post delete "$SP_ID" --force

echo "== Plugins =="
wp plugin delete akismet hello 2>/dev/null || true
wp plugin install gutenberg create-block-theme query-monitor debug-bar user-switching regenerate-thumbnails wp-mail-logging --activate

echo "== Themes =="
wp theme activate twentytwentyfive || true
wp theme delete twentytwentyfour twentytwentythree 2>/dev/null || true

echo "== Language (English UK) =="
wp language core install en_GB >/dev/null 2>&1 || true
wp language core activate en_GB >/dev/null 2>&1 || true
wp option update WPLANG en_GB >/dev/null 2>&1 || true
wp config delete WPLANG >/dev/null 2>&1 || wp config set WPLANG en_GB --type=constant >/dev/null 2>&1 || true
wp language plugin install --all en_GB >/dev/null 2>&1 || true
wp language theme install --all en_GB >/dev/null 2>&1 || true
for USER_ID in $(wp user list --field=ID); do wp user meta update "$USER_ID" locale en_GB >/dev/null || true; done

echo "== Discussion =="
wp option update comments_notify 0
wp option update moderation_notify 0
wp option update default_ping_status 'closed'
wp option update comment_moderation 1
wp option update comment_previously_approved 0

echo "== Media defaults (block-theme friendly) =="
# Thumbnail: square grids/cards
wp option update thumbnail_size_w 320
wp option update thumbnail_size_h 320
wp option update thumbnail_crop 1
# Medium/Large: width-only (height 0 keeps aspect)
wp option update medium_size_w 900; wp option update medium_size_h 0
wp option update medium_large_size_w 1536; wp option update medium_large_size_h 0
wp option update large_size_w 1400; wp option update large_size_h 0
wp option update image_default_size 'large'

# Block themes use Navigation/Page List blocks; no classic menus/widgets.

echo "== Admin color scheme (Modern) =="
for USER_ID in $(wp user list --field=ID); do wp user meta update "$USER_ID" admin_color modern >/dev/null || true; done

echo "== MU-plugin: emoji & oEmbed cleanup =="
MU_DIR="wp-content/mu-plugins"; mkdir -p "$MU_DIR"
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

# ───────────────────────────────────────────────────────────────────────────────
# STARTER CONTENT: categories, tags, posts (with featured images)
# ───────────────────────────────────────────────────────────────────────────────
echo "== Starter content: taxonomies =="

# Helpers
ensure_term () {
	local TAX="$1" NAME="$2" SLUG="$3" TID
	TID="$(wp term list "$TAX" --field=term_id --slug="$SLUG")"
	if [ -z "$TID" ]; then
		TID="$(wp term create "$TAX" "$NAME" --slug="$SLUG" --porcelain)"
	fi
	echo "$TID"
}

import_image () {
	local URL="$1" MID
	MID="$(wp media import "$URL" --porcelain 2>/dev/null || true)"
	echo "$MID"
}

# 5 categories
CAT_NAMES=( "News" "Projects" "Tutorials" "Opinion" "Notes" )
CAT_SLUGS=( "news" "projects" "tutorials" "opinion" "notes" )
for i in "${!CAT_NAMES[@]}"; do
	ensure_term category "${CAT_NAMES[$i]}" "${CAT_SLUGS[$i]}"
done

# 10 tags
TAG_NAMES=( "photography" "design" "art" "workflow" "tips" "studio" "lighting" "gear" "inspiration" "behind-the-scenes" )
TAG_SLUGS=( "photography" "design" "art" "workflow" "tips" "studio" "lighting" "gear" "inspiration" "behind-the-scenes" )
for i in "${!TAG_NAMES[@]}"; do
	ensure_term post_tag "${TAG_NAMES[$i]}" "${TAG_SLUGS[$i]}"
done

echo "== Starter content: posts =="

# Future date (48 hours from now)
SCHED_DATE="$(php -r 'echo date("Y-m-d H:i:s", time()+172800);')"

# Titles
POST_TITLES=(
	"Welcome to the Site"
	"Behind the Scenes: First Shoot"
	"Five Quick Tips for Better Lighting"
	"Project Log: Week One"
	"Opinion: Why Simplicity Wins"
	"How I Organise My Workflow"
	"Gear Notes: What’s in the Bag"
	"Inspiration Board – August"
	"Studio Setup Checklist"
	"Publishing & Scheduling Test"
)

# Two-paragraph generic copy
read -r -d '' GENERIC_COPY <<'EOT' || true
Photography and film have always felt like a way to translate movement, light, and memory into something lasting. My work often overlaps with dance and performance, where timing and rhythm are just as important as aperture or shutter speed. Teaching has become part of that process too—sharing how tools like cameras, lenses, and even simple setups can make creativity more accessible. Whether I’m testing new gear, revisiting older cameras, or experimenting with different workflows, the focus is always on finding clarity through practice.

At the same time, I’m drawn to the possibilities of the web. WordPress, streaming setups, and custom workflows feel like an extension of the studio, a place where ideas can be built and shared. I like exploring how different pieces—lighting choices, software tools, or even the ergonomics of a workspace—come together to shape the final outcome. The process is rarely perfect, but the mix of art, technology, and curiosity keeps things moving forward.
EOT

# Portable random pickers (no 'shuf' needed)
pick_random_category_slug () {
	local n=${#CAT_SLUGS[@]}
	echo "${CAT_SLUGS[$(( RANDOM % n ))]}"
}
pick_two_distinct_tags_csv () {
	local n=${#TAG_SLUGS[@]}
	local i=$(( RANDOM % n ))
	local j
	while :; do
		j=$(( RANDOM % n ))
		[ "$j" -ne "$i" ] && break
	done
	echo "${TAG_SLUGS[$i]},${TAG_SLUGS[$j]}"
}

# Create posts (no unbound DATE_ARG)
for i in "${!POST_TITLES[@]}"; do
	TITLE="${POST_TITLES[$i]}"

	if [ "$i" -eq 0 ]; then
		STATUS="draft"
	elif [ "$i" -eq 1 ]; then
		STATUS="future"
	else
		STATUS="publish"
	fi

	# Build command safely and optionally add --post_date
	CMD=( wp post create
		--post_type=post
		--post_status="$STATUS"
		--post_title="$TITLE"
		--post_content="$GENERIC_COPY"
	)
	[ "$STATUS" = "future" ] && CMD+=( --post_date="$SCHED_DATE" )

	PID="$("${CMD[@]}" --porcelain)"

	# Random category (1)
	CAT_SLUG="$(pick_random_category_slug)"
	wp post term set "$PID" category "$CAT_SLUG" --by=slug >/dev/null

	# Random tags (2 distinct)
	TAGS_CSV="$(pick_two_distinct_tags_csv)"
	wp post term set "$PID" post_tag "$TAGS_CSV" --by=slug --append >/dev/null

	# Featured image via Picsum
	IMG_URL="https://picsum.photos/seed/wpseed$((1000+i))/1600/900"
	MID="$(import_image "$IMG_URL")"
	[ -n "$MID" ] && wp post meta update "$PID" _thumbnail_id "$MID" >/dev/null

	wp post update "$PID" --post_excerpt="Starter excerpt for \"$TITLE\"." >/dev/null

	echo "  • Post #$((i+1)) ($STATUS): $TITLE (Cat: $CAT_SLUG, Tags: $TAGS_CSV)"
done

echo "== Finalize =="
wp rewrite flush

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
mins=$(( ELAPSED / 60 ))
secs=$(( ELAPSED % 60 ))

echo -e "
Bootstrap complete (with starter content).
Execution time: ${mins}m ${secs}s
"
