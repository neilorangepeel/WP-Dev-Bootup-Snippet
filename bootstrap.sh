#!/usr/bin/env bash
set -euo pipefail

START_TIME=$(date +%s)

# Fast wrapper that skips plugins & themes to speed up CLI boots
wpq() { wp --skip-plugins --skip-themes "$@"; }

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
wpq core is-installed >/dev/null 2>&1 || { echo "WP-CLI can't load WordPress (check path/db)."; exit 1; }

echo "== wp-config constants =="
# String constants (let WP-CLI add quotes)
wpq config set WP_ENVIRONMENT_TYPE development --type=constant 2>/dev/null || true
wpq config set WP_MEMORY_LIMIT 256M --type=constant 2>/dev/null || true
# Booleans / ints (raw)
wpq config set WP_DEBUG true --type=constant --raw 2>/dev/null || true
wpq config set WP_DEBUG_LOG true --type=constant --raw 2>/dev/null || true
wpq config set WP_DEBUG_DISPLAY false --type=constant --raw 2>/dev/null || true
wpq config set SCRIPT_DEBUG true --type=constant --raw 2>/dev/null || true
wpq config set DISALLOW_FILE_EDIT true --type=constant --raw 2>/dev/null || true
wpq config set WP_DISABLE_FATAL_ERROR_HANDLER true --type=constant --raw 2>/dev/null || true
wpq config set WP_POST_REVISIONS 10 --type=constant --raw 2>/dev/null || true

# ───────────────────────────────────────────────────────────────────────────────
# EVERYTHING BELOW RUNS IN ONE WP BOOTSTRAP (fast)
# ───────────────────────────────────────────────────────────────────────────────
echo "== Fast site setup + starter content (single eval) =="

wp eval-file - <<'PHP'
<?php
// Speed helpers
wp_defer_term_counting( true );
wp_defer_comment_counting( true );
wp_suspend_cache_invalidation( true );
if ( function_exists('set_time_limit') ) @set_time_limit(0);

// ---------- Core options / settings ----------
update_option('timezone_string', 'Europe/London');
update_option('blogdescription', 'Just another site');
update_option('date_format', 'j F Y');
update_option('time_format', 'H:i');
update_option('blog_public', 0);

// Permalinks: store structure now; flush later via CLI once
update_option('permalink_structure', '/%postname%/');

// Media defaults
update_option('thumbnail_size_w', 320);
update_option('thumbnail_size_h', 320);
update_option('thumbnail_crop', 1);
update_option('medium_size_w', 900);
update_option('medium_size_h', 0);
update_option('medium_large_size_w', 1536);
update_option('medium_large_size_h', 0);
update_option('large_size_w', 1400);
update_option('large_size_h', 0);
update_option('image_default_size', 'large');

// Discussion
update_option('comments_notify', 0);
update_option('moderation_notify', 0);
update_option('default_ping_status', 'closed');
update_option('comment_moderation', 1);
update_option('comment_previously_approved', 0);

// User locale + admin color for all users
$users = get_users([ 'fields' => ['ID'] ]);
foreach ($users as $u) {
	update_user_meta($u->ID, 'locale', 'en_GB');
	update_user_meta($u->ID, 'admin_color', 'modern');
}

// ---------- Pages + front/blog ----------
function ensure_page_id($title, $slug){
	$q = new WP_Query([
		'post_type'      => 'page',
		'post_status'    => 'any',
		'name'           => $slug,
		'posts_per_page' => 1,
		'no_found_rows'  => true,
		'fields'         => 'ids',
	]);
	if ($q->have_posts()) return intval($q->posts[0]);

	return wp_insert_post([
		'post_type'   => 'page',
		'post_status' => 'publish',
		'post_title'  => $title,
		'post_name'   => $slug,
	]);
}
$home_id    = ensure_page_id('Home','home');
$about_id   = ensure_page_id('About','about');
$blog_id    = ensure_page_id('Blog','blog');
$contact_id = ensure_page_id('Contact','contact');

update_option('show_on_front', 'page');
update_option('page_on_front', $home_id);
update_option('page_for_posts', $blog_id);

// Delete WP defaults if present
foreach (['Hello world!','Sample Page'] as $title) {
	$q = new WP_Query([
		'post_status'    => 'any',
		'title'          => $title,
		'posts_per_page' => 1,
		'no_found_rows'  => true,
		'fields'         => 'ids',
	]);
	if ($q->have_posts()) wp_delete_post(intval($q->posts[0]), true);
}

// ---------- Theme ----------
if ( function_exists('switch_theme') ) {
	$curr = wp_get_theme()->get_stylesheet();
	if ( $curr !== 'twentytwentyfive' ) {
		$tt5 = wp_get_theme('twentytwentyfive');
		if ( $tt5 && $tt5->exists() ) {
			switch_theme('twentytwentyfive');
		}
	}
}

// ---------- Taxonomies ----------
function ensure_term_id($taxonomy, $name, $slug) {
	$term = get_term_by('slug', $slug, $taxonomy);
	if ($term && !is_wp_error($term)) return intval($term->term_id);
	$res = wp_insert_term($name, $taxonomy, ['slug' => $slug]);
	if (is_wp_error($res)) return 0;
	return intval($res['term_id']);
}

$cat_names = ['News','Projects','Tutorials','Opinion','Notes'];
$cat_ids   = [];
foreach ($cat_names as $name) {
	$cat_ids[] = ensure_term_id('category', $name, sanitize_title($name));
}

$tag_names = ['photography','design','art','workflow','tips','studio','lighting','gear','inspiration','behind-the-scenes'];
foreach ($tag_names as $name) {
	ensure_term_id('post_tag', $name, sanitize_title($name));
}

// ---------- Placeholder image (always 1600x900) ----------
function make_placeholder_attachment($seed, $parent_post_id = 0) {
	$w = 1600; $h = 900; // fixed dimensions

	$uploads = wp_upload_dir();
	if ( ! empty($uploads['error']) ) return 0;
	wp_mkdir_p($uploads['path']);
	$file = trailingslashit($uploads['path']) . "placeholder-$seed.jpg";

	if ( ! function_exists('imagecreatetruecolor') ) return 0;
	$im = imagecreatetruecolor($w, $h);
	mt_srand($seed);
	$bg = imagecolorallocate($im, mt_rand(40,200), mt_rand(40,200), mt_rand(40,200));
	imagefilledrectangle($im, 0, 0, $w, $h, $bg);
	imagejpeg($im, $file, 80);
	imagedestroy($im);

	require_once ABSPATH . 'wp-admin/includes/image.php';
	$filetype = wp_check_filetype(basename($file), null);
	$attachment_id = wp_insert_attachment([
		'post_mime_type' => $filetype['type'],
		'post_title'     => "Placeholder $seed",
		'post_content'   => '',
		'post_status'    => 'inherit',
	], $file, $parent_post_id);

	if ( is_wp_error($attachment_id) || ! $attachment_id ) return 0;
	$attach_data = wp_generate_attachment_metadata($attachment_id, $file);
	wp_update_attachment_metadata($attachment_id, $attach_data);

	return (int) $attachment_id;
}

// ---------- Posts ----------
$post_titles = [
  'Welcome to the Site',
  'Behind the Scenes: First Shoot',
  'Five Quick Tips for Better Lighting',
  'Project Log: Week One',
  'Opinion: Why Simplicity Wins',
  'How I Organise My Workflow',
  'Gear Notes: What’s in the Bag',
  'Inspiration Board – August',
  'Studio Setup Checklist',
  'Publishing & Scheduling Test',
];

$copy = "Photography and film have always felt like a way to translate movement, light, and memory into something lasting. My work often overlaps with dance and performance, where timing and rhythm are just as important as aperture or shutter speed. Teaching has become part of that process too—sharing how tools like cameras, lenses, and even simple setups can make creativity more accessible. Whether I’m testing new gear, revisiting older cameras, or experimenting with different workflows, the focus is always on finding clarity through practice.\n\nAt the same time, I’m drawn to the possibilities of the web. WordPress, streaming setups, and custom workflows feel like an extension of the studio, a place where ideas can be built and shared. I like exploring how different pieces—lighting choices, software tools, or even the ergonomics of a workspace—come together to shape the final outcome. The process is rarely perfect, but the mix of art, technology, and curiosity keeps things moving forward.";

$sched_gmt = gmdate('Y-m-d H:i:s', time() + 172800); // +48h

foreach ($post_titles as $i => $title) {
	$status = ($i === 0) ? 'draft' : (($i === 1) ? 'future' : 'publish');
	$postarr = [
		'post_title'   => $title,
		'post_content' => $copy,
		'post_status'  => $status,
		'post_type'    => 'post',
	];
	if ($status === 'future') {
		$postarr['post_date'] = get_date_from_gmt($sched_gmt);
	}

	$pid = wp_insert_post($postarr, true);
	if ( is_wp_error($pid) || ! $pid ) { echo "Failed to create: $title\n"; continue; }

	$cat_id = $cat_ids[array_rand($cat_ids)];
	$tag_a  = $tag_names[array_rand($tag_names)];
	do { $tag_b = $tag_names[array_rand($tag_names)]; } while ($tag_b === $tag_a);

	wp_set_post_terms($pid, [$cat_id], 'category', false);
	wp_set_post_terms($pid, [$tag_a, $tag_b], 'post_tag', false);

	$mid = make_placeholder_attachment(1000 + $i, $pid);
	if ($mid) set_post_thumbnail($pid, $mid);

	wp_update_post(['ID' => $pid, 'post_excerpt' => "Starter excerpt for \"$title\"."]);

	echo " • Post #" . ($i+1) . " ($status): $title (Cat: $cat_id, Tags: $tag_a,$tag_b, MID: " . ($mid ?: 'none') . ")\n";
}

// Restore performance flags
wp_defer_term_counting( false );
wp_defer_comment_counting( false );
wp_suspend_cache_invalidation( false );
PHP

# ───────────────────────────────────────────────────────────────────────────────
# MU-plugin: emoji & oEmbed cleanup
# ───────────────────────────────────────────────────────────────────────────────
echo "== MU-plugin: emoji & oEmbed cleanup =="
MU_DIR="wp-content/mu-plugins"; mkdir -p "$MU_DIR"
cat > "$MU_DIR/dev-tweaks.php" <<'PHP'
<?php
/*
Plugin Name: Dev Tweaks (disable emojis & oEmbed)
Description: Small front-end cleanups for dev/staging.
*/
add_action('init', function () {
	remove_action('wp_head', 'print_emoji_detection_script', 7);
	remove_action('admin_print_scripts', 'print_emoji_detection_script');
	remove_action('wp_print_styles', 'print_emoji_styles');
	remove_action('admin_print_styles', 'print_emoji_styles');
	remove_filter('the_content_feed', 'wp_staticize_emoji');
	remove_filter('comment_text_rss', 'wp_staticize_emoji');
	remove_filter('wp_mail', 'wp_staticize_emoji_for_email');
	remove_action('wp_head', 'wp_oembed_add_discovery_links');
	remove_action('wp_head', 'wp_oembed_add_host_js');
	remove_filter('oembed_dataparse', 'wp_filter_oembed_result', 10);
	add_filter('embed_oembed_discover', '__return_false');
});
PHP

# ───────────────────────────────────────────────────────────────────────────────
# Themes — delete extras
# ───────────────────────────────────────────────────────────────────────────────
echo "== Themes =="
wpq theme delete twentytwentyfour twentytwentythree 2>/dev/null || true

# ───────────────────────────────────────────────────────────────────────────────
# Plugins — install/activate at the END
# ───────────────────────────────────────────────────────────────────────────────
echo "== Plugins (installed at end for speed) =="
wp plugin delete akismet hello 2>/dev/null || true
wp plugin install gutenberg create-block-theme query-monitor debug-bar user-switching regenerate-thumbnails wp-mail-logging --activate

# ───────────────────────────────────────────────────────────────────────────────
# Finalize
# ───────────────────────────────────────────────────────────────────────────────
echo "== Finalize =="
wp rewrite flush

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
mins=$(( ELAPSED / 60 ))
secs=$(( ELAPSED % 60 ))

echo -e "
Bootstrap complete (fast path with single WP bootstrap for content).
Execution time: ${mins}m ${secs}s
"
