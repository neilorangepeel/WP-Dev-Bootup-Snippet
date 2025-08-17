#!/usr/bin/env bash
set -euo pipefail

START_TIME=$(date +%s)

# Fast wrapper: skip plugins/themes to speed up CLI boot
wpq() { wp --skip-plugins --skip-themes "$@"; }

# ── Sanity
[ -f wp-config.php ] || { echo "wp-config.php not found in $PWD"; exit 1; }
php -l wp-config.php >/dev/null 2>&1 || {
	echo "Fixing wp-config.php syntax…"
	cp wp-config.php "wp-config.php.bak.$(date +%s)"
	# Quote memory constants
	perl -i -pe "s/define\(\s*([''])WP_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT','\$2\$3')/ig" wp-config.php
	perl -i -pe "s/define\(\s*([''])WP_MAX_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT','\$2\$3')/ig" wp-config.php
	perl -i -pe "s/define\(\s*WP_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT','\$1\$2')/ig" wp-config.php
	perl -i -pe "s/define\(\s*WP_MAX_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT','\$1\$2')/ig" wp-config.php
	# Quote environment type
	perl -i -pe "s/define\(\s*([''])WP_ENVIRONMENT_TYPE\1\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE','\$2')/i" wp-config.php
	perl -i -pe "s/define\(\s*WP_ENVIRONMENT_TYPE\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE','\$1')/i" wp-config.php
	php -l wp-config.php >/dev/null || { echo "wp-config.php still has a syntax error (see php -l)."; exit 1; }
}

# ── WordPress loads?
wpq core is-installed >/dev/null 2>&1 || { echo "WP-CLI can't load WordPress (check path/db)."; exit 1; }

echo "== Config constants =="
wpq config set WP_ENVIRONMENT_TYPE development --type=constant 2>/dev/null || true
wpq config set WP_MEMORY_LIMIT 256M --type=constant 2>/dev/null || true
wpq config set WP_DEBUG true --type=constant --raw 2>/dev/null || true
wpq config set WP_DEBUG_LOG true --type=constant --raw 2>/dev/null || true
wpq config set WP_DEBUG_DISPLAY false --type=constant --raw 2>/dev/null || true
wpq config set SCRIPT_DEBUG true --type=constant --raw 2>/dev/null || true
wpq config set DISALLOW_FILE_EDIT true --type=constant --raw 2>/dev/null || true
wpq config set WP_DISABLE_FATAL_ERROR_HANDLER true --type=constant --raw 2>/dev/null || true
wpq config set WP_POST_REVISIONS 10 --type=constant --raw 2>/dev/null || true

echo "== Fast site setup + starter content (single eval) =="
wp eval-file - <<'PHP'
<?php
// Speed flags
wp_defer_term_counting(true);
wp_defer_comment_counting(true);
wp_suspend_cache_invalidation(true);
if (function_exists('set_time_limit')) @set_time_limit(0);

/** Core/site options (permalinks flushed later) */
update_option('timezone_string', 'Europe/London');
update_option('blogdescription', 'Just another site');
update_option('date_format', 'j F Y');
update_option('time_format', 'H:i');
update_option('blog_public', 0);
update_option('permalink_structure', '/%postname%/');
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

/** User prefs */
foreach (get_users(['fields'=>['ID']]) as $u) {
	update_user_meta($u->ID, 'locale', 'en_GB');
	update_user_meta($u->ID, 'admin_color', 'modern');
}

/** Ensure pages + set front/blog */
function ensure_page_id($title, $slug) {
	$q = new WP_Query([
		'post_type'=>'page','post_status'=>'any','name'=>$slug,
		'posts_per_page'=>1,'no_found_rows'=>true,'fields'=>'ids',
	]);
	if ($q->have_posts()) return (int)$q->posts[0];
	return (int) wp_insert_post([
		'post_type'=>'page','post_status'=>'publish','post_title'=>$title,'post_name'=>$slug,
	]);
}
$home_id = ensure_page_id('Home','home');
$about_id = ensure_page_id('About','about');
$blog_id = ensure_page_id('Blog','blog');
$contact_id = ensure_page_id('Contact','contact');
update_option('show_on_front','page');
update_option('page_on_front',$home_id);
update_option('page_for_posts',$blog_id);

/** Delete WP defaults robustly by slug and title */
$slugs = ['hello-world','sample-page'];
$ids = get_posts([
	'post_type'=>['post','page'],'post_status'=>'any','posts_per_page'=>-1,
	'no_found_rows'=>true,'fields'=>'ids','post_name__in'=>$slugs,
]);
foreach ($ids as $pid) wp_delete_post($pid, true);
$maybe = get_posts([
	'post_type'=>['post','page'],'post_status'=>'any','s'=>'Sample Page',
	'posts_per_page'=>-1,'no_found_rows'=>true,'fields'=>'ids',
]);
foreach ($maybe as $pid) {
	$p = get_post($pid);
	if ($p && in_array(sanitize_title($p->post_title), $slugs, true)) wp_delete_post($pid, true);
}

/** Activate Twenty Twenty-Five (if present) */
if (function_exists('switch_theme')) {
	if (wp_get_theme()->get_stylesheet() !== 'twentytwentyfive') {
		$t = wp_get_theme('twentytwentyfive');
		if ($t && $t->exists()) switch_theme('twentytwentyfive');
	}
}

/** Helper: ensure term */
function ensure_term_id($tax, $name) {
	$slug = sanitize_title($name);
	$term = get_term_by('slug', $slug, $tax);
	if ($term && !is_wp_error($term)) return (int)$term->term_id;
	$res = wp_insert_term($name, $tax, ['slug'=>$slug]);
	return is_wp_error($res) ? 0 : (int)$res['term_id'];
}

/** Categories + tags */
$cat_names = ['News','Projects','Tutorials','Opinion','Notes'];
$cat_ids = array_values(array_filter(array_map(fn($n)=>ensure_term_id('category',$n), $cat_names)));
$tag_names = ['photography','design','art','workflow','tips','studio','lighting','gear','inspiration','behind-the-scenes'];
foreach ($tag_names as $n) ensure_term_id('post_tag',$n);

/** Local coloured placeholder (always 1600x900) */
function make_placeholder_attachment($seed, $parent_post_id = 0) {
	$w=1600; $h=900;
	$uploads = wp_upload_dir(); if (!empty($uploads['error'])) return 0;
	wp_mkdir_p($uploads['path']);
	$file = trailingslashit($uploads['path'])."placeholder-$seed.jpg";

	if (!function_exists('imagecreatetruecolor')) return 0;
	$im = imagecreatetruecolor($w,$h);
	mt_srand($seed);
	$bg = imagecolorallocate($im, mt_rand(40,200), mt_rand(40,200), mt_rand(40,200));
	imagefilledrectangle($im,0,0,$w,$h,$bg);
	imagejpeg($im,$file,80); imagedestroy($im);

	require_once ABSPATH.'wp-admin/includes/image.php';
	$type = wp_check_filetype(basename($file), null);
	$att = wp_insert_attachment([
		'post_mime_type'=>$type['type'],'post_title'=>"Placeholder $seed",
		'post_content'=>'','post_status'=>'inherit',
	], $file, $parent_post_id);
	if (is_wp_error($att) || !$att) return 0;

	$meta = wp_generate_attachment_metadata($att,$file);
	wp_update_attachment_metadata($att,$meta);
	return (int)$att;
}

/** Posts (10: draft + future + 8 published), random 1 category + 2 tags, excerpt + featured image */
$titles = [
 'Welcome to the Site','Behind the Scenes: First Shoot','Five Quick Tips for Better Lighting',
 'Project Log: Week One','Opinion: Why Simplicity Wins','How I Organise My Workflow',
 'Gear Notes: What’s in the Bag','Inspiration Board – August','Studio Setup Checklist','Publishing & Scheduling Test',
];
$copy = "Photography and film have always felt like a way to translate movement, light, and memory into something lasting. My work often overlaps with dance and performance, where timing and rhythm are just as important as aperture or shutter speed. Teaching has become part of that process too—sharing how tools like cameras, lenses, and even simple setups can make creativity more accessible. Whether I’m testing new gear, revisiting older cameras, or experimenting with different workflows, the focus is always on finding clarity through practice.\n\nAt the same time, I’m drawn to the possibilities of the web. WordPress, streaming setups, and custom workflows feel like an extension of the studio, a place where ideas can be built and shared. I like exploring how different pieces—lighting choices, software tools, or even the ergonomics of a workspace—come together to shape the final outcome. The process is rarely perfect, but the mix of art, technology, and curiosity keeps things moving forward.";
$sched_gmt = gmdate('Y-m-d H:i:s', time()+172800);

foreach ($titles as $i=>$title) {
	$status = $i===0 ? 'draft' : ($i===1 ? 'future' : 'publish');
	$post = [
		'post_title'=>$title,'post_content'=>$copy,'post_status'=>$status,'post_type'=>'post'
	];
	if ($status==='future') $post['post_date'] = get_date_from_gmt($sched_gmt);

	$pid = wp_insert_post($post, true); if (is_wp_error($pid) || !$pid) { echo "Failed: $title\n"; continue; }

	$cat_id = $cat_ids[array_rand($cat_ids)];
	$t1 = $tag_names[array_rand($tag_names)];
	do { $t2 = $tag_names[array_rand($tag_names)]; } while ($t2===$t1);

	wp_set_post_terms($pid, [$cat_id], 'category', false);
	wp_set_post_terms($pid, [$t1,$t2], 'post_tag', false);

	$mid = make_placeholder_attachment(1000+$i, $pid);
	if ($mid) set_post_thumbnail($pid, $mid);

	wp_update_post(['ID'=>$pid,'post_excerpt'=>"Starter excerpt for \"$title\"."]);
	echo " • Post #".($i+1)." ($status): $title (Cat: $cat_id, Tags: $t1,$t2, MID: ".($mid?:'none').")\n";
}

// Restore flags
wp_defer_term_counting(false);
wp_defer_comment_counting(false);
wp_suspend_cache_invalidation(false);
PHP

echo "== MU-plugin =="
MU_DIR="wp-content/mu-plugins"; mkdir -p "$MU_DIR"
cat > "$MU_DIR/dev-tweaks.php" <<'PHP'
<?php
/*
Plugin Name: Dev Tweaks (disable emojis & oEmbed)
Description: Small front-end cleanups for dev/staging.
*/
add_action('init', function () {
	remove_action('wp_head','print_emoji_detection_script',7);
	remove_action('admin_print_scripts','print_emoji_detection_script');
	remove_action('wp_print_styles','print_emoji_styles');
	remove_action('admin_print_styles','print_emoji_styles');
	remove_filter('the_content_feed','wp_staticize_emoji');
	remove_filter('comment_text_rss','wp_staticize_emoji');
	remove_filter('wp_mail','wp_staticize_emoji_for_email');
	remove_action('wp_head','wp_oembed_add_discovery_links');
	remove_action('wp_head','wp_oembed_add_host_js');
	remove_filter('oembed_dataparse','wp_filter_oembed_result',10);
	add_filter('embed_oembed_discover','__return_false');
});
PHP

echo "== Themes =="
wpq theme delete twentytwentyfour twentytwentythree 2>/dev/null || true

echo "== Plugins =="
wp plugin delete akismet hello 2>/dev/null || true
wp plugin install gutenberg create-block-theme query-monitor debug-bar user-switching regenerate-thumbnails wp-mail-logging --activate

echo "== Finalize =="
wp rewrite flush

END_TIME=$(date +%s)
ELAPSED=$((END_TIME-START_TIME))
printf "\nBootstrap complete (fast, single-WP-bootstrap).\nExecution time: %dm %ds\n" $((ELAPSED/60)) $((ELAPSED%60))
