#!/usr/bin/env bash
set -euo pipefail
START_TIME=$(date +%s)
wpq(){ wp --skip-plugins --skip-themes "$@"; }

[ -f wp-config.php ] || { echo "wp-config.php not found"; exit 1; }
php -l wp-config.php >/dev/null 2>&1 || {
  cp wp-config.php "wp-config.php.bak.$(date +%s)"
  perl -i -pe "s/define\(\s*([''])WP_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT','\$2\$3')/ig" wp-config.php
  perl -i -pe "s/define\(\s*([''])WP_MAX_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT','\$2\$3')/ig" wp-config.php
  perl -i -pe "s/define\(\s*WP_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT','\$1\$2')/ig" wp-config.php
  perl -i -pe "s/define\(\s*WP_MAX_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT','\$1\$2')/ig" wp-config.php
  perl -i -pe "s/define\(\s*([''])WP_ENVIRONMENT_TYPE\1\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE','\$2')/i" wp-config.php
  perl -i -pe "s/define\(\s*WP_ENVIRONMENT_TYPE\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE','\$1')/i" wp-config.php
  php -l wp-config.php >/dev/null || { echo "wp-config.php still has a syntax error"; exit 1; }
}

wpq core is-installed >/dev/null 2>&1 || { echo "WP-CLI can't load WordPress"; exit 1; }

wpq config set WP_ENVIRONMENT_TYPE development --type=constant 2>/dev/null || true
wpq config set WP_MEMORY_LIMIT 256M --type=constant 2>/dev/null || true
wpq config set WP_DEBUG true --type=constant --raw 2>/dev/null || true
wpq config set WP_DEBUG_LOG true --type=constant --raw 2>/dev/null || true
wpq config set WP_DEBUG_DISPLAY false --type=constant --raw 2>/dev/null || true
wpq config set SCRIPT_DEBUG true --type=constant --raw 2>/dev/null || true
wpq config set DISALLOW_FILE_EDIT true --type=constant --raw 2>/dev/null || true
wpq config set WP_DISABLE_FATAL_ERROR_HANDLER true --type=constant --raw 2>/dev/null || true
wpq config set WP_POST_REVISIONS 10 --type=constant --raw 2>/dev/null || true

wp eval-file - <<'PHP'
<?php
wp_defer_term_counting(true); wp_defer_comment_counting(true); wp_suspend_cache_invalidation(true);
if(function_exists('set_time_limit')) @set_time_limit(0);

update_option('timezone_string','Europe/London');
update_option('blogdescription','Just another site');
update_option('date_format','j F Y'); update_option('time_format','H:i'); update_option('blog_public',0);
update_option('permalink_structure','/%postname%/');
update_option('thumbnail_size_w',320); update_option('thumbnail_size_h',320); update_option('thumbnail_crop',1);
update_option('medium_size_w',900); update_option('medium_size_h',0);
update_option('medium_large_size_w',1536); update_option('medium_large_size_h',0);
update_option('large_size_w',1400); update_option('large_size_h',0);
update_option('image_default_size','large');

foreach(get_users(['fields'=>['ID']]) as $u){ update_user_meta($u->ID,'locale','en_GB'); update_user_meta($u->ID,'admin_color','modern'); }

$ensure_page=function($title,$slug){
  $q=new WP_Query(['post_type'=>'page','post_status'=>'any','name'=>$slug,'posts_per_page'=>1,'no_found_rows'=>true,'fields'=>'ids']);
  return $q->have_posts()?(int)$q->posts[0]:(int)wp_insert_post(['post_type'=>'page','post_status'=>'publish','post_title'=>$title,'post_name'=>$slug]);
};
$home=$ensure_page('Home','home'); $about=$ensure_page('About','about'); $blog=$ensure_page('Blog','blog'); $contact=$ensure_page('Contact','contact');
update_option('show_on_front','page'); update_option('page_on_front',$home); update_option('page_for_posts',$blog);

$ids=get_posts(['post_type'=>['post','page'],'post_status'=>'any','posts_per_page'=>-1,'no_found_rows'=>true,'fields'=>'ids','post_name__in'=>['hello-world','sample-page']]);
foreach($ids as $id) wp_delete_post($id,true);
$maybe=get_posts(['post_type'=>['post','page'],'post_status'=>'any','s'=>'Sample Page','posts_per_page'=>-1,'no_found_rows'=>true,'fields'=>'ids']);
foreach($maybe as $id){ $p=get_post($id); if($p && in_array(sanitize_title($p->post_title),['hello-world','sample-page'],true)) wp_delete_post($id,true); }

if(function_exists('switch_theme')){ if(wp_get_theme()->get_stylesheet()!=='twentytwentyfive'){ $t=wp_get_theme('twentytwentyfive'); if($t && $t->exists()) switch_theme('twentytwentyfive'); } }

$ensure_term=function($tax,$name){ $slug=sanitize_title($name); $t=get_term_by('slug',$slug,$tax); if($t&&!is_wp_error($t)) return (int)$t->term_id; $r=wp_insert_term($name,$tax,['slug'=>$slug]); return is_wp_error($r)?0:(int)$r['term_id']; };
$cat_ids=array_values(array_filter(array_map(fn($n)=>$ensure_term('category',$n),['News','Projects','Tutorials','Opinion','Notes'])));
$tags=['photography','design','art','workflow','tips','studio','lighting','gear','inspiration','behind-the-scenes']; foreach($tags as $n){ $ensure_term('post_tag',$n); }

$make_img=function($seed,$parent=0){ $w=1600;$h=900; $u=wp_upload_dir(); if(!empty($u['error'])) return 0; wp_mkdir_p($u['path']); $f=trailingslashit($u['path'])."placeholder-$seed.jpg";
  if(!function_exists('imagecreatetruecolor')) return 0; $im=imagecreatetruecolor($w,$h); mt_srand($seed);
  $bg=imagecolorallocate($im,mt_rand(40,200),mt_rand(40,200),mt_rand(40,200)); imagefilledrectangle($im,0,0,$w,$h,$bg); imagejpeg($im,$f,80); imagedestroy($im);
  require_once ABSPATH.'wp-admin/includes/image.php'; $t=wp_check_filetype(basename($f),null);
  $att=wp_insert_attachment(['post_mime_type'=>$t['type'],'post_title'=>"Placeholder $seed",'post_content'=>'','post_status'=>'inherit'],$f,$parent);
  if(is_wp_error($att)||!$att) return 0; $meta=wp_generate_attachment_metadata($att,$f); wp_update_attachment_metadata($att,$meta); return (int)$att;
};

$titles=['Welcome to the Site','Behind the Scenes: First Shoot','Five Quick Tips for Better Lighting','Project Log: Week One','Opinion: Why Simplicity Wins','How I Organise My Workflow','Gear Notes: What’s in the Bag','Inspiration Board – August','Studio Setup Checklist','Publishing & Scheduling Test'];
$copy="Photography and film have always felt like a way to translate movement, light, and memory into something lasting. My work often overlaps with dance and performance, where timing and rhythm are just as important as aperture or shutter speed. Teaching has become part of that process too—sharing how tools like cameras, lenses, and even simple setups can make creativity more accessible. Whether I’m testing new gear, revisiting older cameras, or experimenting with different workflows, the focus is always on finding clarity through practice.\n\nAt the same time, I’m drawn to the possibilities of the web. WordPress, streaming setups, and custom workflows feel like an extension of the studio, a place where ideas can be built and shared. I like exploring how different pieces—lighting choices, software tools, or even the ergonomics of a workspace—come together to shape the final outcome. The process is rarely perfect, but the mix of art, technology, and curiosity keeps things moving forward.";
$sched_gmt=gmdate('Y-m-d H:i:s',time()+172800);

foreach($titles as $i=>$title){
  $status=$i===0?'draft':($i===1?'future':'publish');
  $post=['post_title'=>$title,'post_content'=>$copy,'post_status'=>$status,'post_type'=>'post'];
  if($status==='future') $post['post_date']=get_date_from_gmt($sched_gmt);
  $pid=wp_insert_post($post,true); if(is_wp_error($pid)||!$pid){ echo "Failed: $title\n"; continue; }
  $cat=$cat_ids[array_rand($cat_ids)]; $t1=$tags[array_rand($tags)]; do{$t2=$tags[array_rand($tags)];}while($t2===$t1);
  wp_set_post_terms($pid,[$cat],'category',false); wp_set_post_terms($pid,[$t1,$t2],'post_tag',false);
  $mid=$make_img(1000+$i,$pid); if($mid) set_post_thumbnail($pid,$mid);
  wp_update_post(['ID'=>$pid,'post_excerpt'=>"Starter excerpt for \"$title\"."]);
  echo " • #".($i+1)." $status: $title (Cat:$cat Tags:$t1,$t2 MID:".($mid?:'none').")\n";
}

wp_defer_term_counting(false); wp_defer_comment_counting(false); wp_suspend_cache_invalidation(false);
PHP

mkdir -p wp-content/mu-plugins
cat > wp-content/mu-plugins/dev-tweaks.php <<'PHP'
<?php
/*
Plugin Name: Dev Tweaks
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

wpq theme delete twentytwentyfour twentytwentythree 2>/dev/null || true

wp plugin delete akismet hello 2>/dev/null || true
wp plugin install gutenberg create-block-theme query-monitor debug-bar user-switching regenerate-thumbnails wp-mail-logging --activate

wp rewrite flush

END_TIME=$(date +%s); ELAPSED=$((END_TIME-START_TIME))
printf "\nBootstrap complete.\nExecution time: %dm %ds\n" $((ELAPSED/60)) $((ELAPSED%60))
