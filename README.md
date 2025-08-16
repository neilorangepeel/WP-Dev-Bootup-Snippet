# Studio Starter Bootstrap

A handy script + MU‑plugin combo to instantly configure a fresh **Studio by WordPress** site with your preferred development defaults — optimised for **block themes**.

---

## 🚀 Quick Start

### One‑liner (recommended)
Run directly from GitHub to always use the latest version:

```bash
cd /path/to/your/studio-site
curl -sSL https://raw.githubusercontent.com/YOUR-USERNAME/YOUR-REPO/main/bootstrap.sh | bash
```

Replace `YOUR-USERNAME/YOUR-REPO` with your GitHub repo path. This will:
- Patch `wp-config.php` (debug constants, memory, environment) and **self‑heal** common mistakes.
- Apply timezone, permalinks, date/time formats, and set **site language to English (UK)**.
- Create **Home**, **About**, **Blog**, **Contact** pages and set a static front page.
- Delete default content.
- Install/activate your plugin set (Gutenberg, Create Block Theme, Query Monitor, etc.).
- Set **block‑theme friendly media sizes**.
- Disable comment notifications, pingbacks/trackbacks.
- Set all users’ **Admin Color Scheme** to **Modern**.
- Add a tiny MU‑plugin to disable **emoji** and **oEmbed** extras.

### Manual run
1. Copy `bootstrap.sh` into your site root.
2. `chmod +x bootstrap.sh`
3. `./bootstrap.sh`

---

## 📦 What it does (at a glance)

### 🔧 Config (`wp-config.php`)
- `WP_ENVIRONMENT_TYPE='development'`
- `WP_DEBUG=true`, `WP_DEBUG_LOG=true`, `WP_DEBUG_DISPLAY=false`
- `SCRIPT_DEBUG=true`, `DISALLOW_FILE_EDIT=true`
- `WP_MEMORY_LIMIT='256M'`
- `WP_DISABLE_FATAL_ERROR_HANDLER=true`
- `WP_POST_REVISIONS=10`

### 🌍 Options
- Site language → **English (UK)** (`en_GB`) — enforced via `language core activate` **and** `WPLANG` option
- Timezone → `Europe/London`
- Permalinks → `/%postname%/`
- Tagline → `'Just another site'`
- Date format → `j F Y` · Time format → `H:i`
- Discourage search engines (dev/staging)

### 📰 Content
- Creates **Home**, **About**, **Blog**, **Contact** pages
- Sets static front page + posts page
- Removes “Hello world!” + “Sample Page”

### 🔌 Plugins
- Deletes: Akismet, Hello Dolly
- Installs + activates:
  - Gutenberg · Create Block Theme · Query Monitor · Debug Bar · User Switching · Regenerate Thumbnails · WP Mail Logging

### 🎨 Themes
- Activates **Twenty Twenty‑Five**
- Deletes older default themes

### 💬 Discussion
- Turns off email notifications
- Disables pingbacks/trackbacks
- Requires moderation (no auto‑approve)

### 🖼 Media (block‑theme friendly)
- **Thumbnail**: 320 × 320 (cropped)
- **Medium**: 900 × auto (height 0)
- **Medium Large**: 1536 × auto
- **Large**: 1400 × auto
- Default insert size: **large**

### 🎛 Admin Color Scheme
- Sets all users’ `admin_color` to **modern** (UI theme in wp‑admin)

### ✨ MU‑plugin: `dev-tweaks.php`
- Disables emoji detection script
- Disables oEmbed discovery and host JS

---

## 🧩 Alfred integration
- Save the one‑liner as a snippet in Alfred (e.g., keyword `;wpboot`).
- Type `;wpboot` in your terminal → it pastes the curl command.

---

## 🧪 Verify (optional)
Quick checks you can run after bootstrapping:

```bash
wp config get WP_ENVIRONMENT_TYPE --type=constant
wp config get WP_MEMORY_LIMIT     --type=constant
wp language core list --status=active   # should show en_GB active
wp option get WPLANG                    # should be en_GB
wp option get permalink_structure
wp option get timezone_string
wp plugin list --status=active
wp option get large_size_w ; wp option get medium_size_w ; wp option get medium_large_size_w
```

---

## 📜 Reference: `bootstrap.sh`
> The script is commented so each step is easy to skim. Keep this file in your repo root and the one‑liner will always fetch the latest version.

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── Sanity: must be in WP site root
[ -f wp-config.php ] || { echo "wp-config.php not found in $PWD"; exit 1; }

# ── Self-heal common wp-config mistakes (unquoted 256M / env type), then re-lint
if ! php -l wp-config.php >/dev/null 2>&1; then
  echo "Fixing wp-config.php syntax…"
  cp wp-config.php "wp-config.php.bak.$(date +%s)"

  # Quote bare memory values like 256M or 512M
  perl -i -pe "s/define\(\s*(['"])WP_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT','\$2\$3')/ig" wp-config.php
  perl -i -pe "s/define\(\s*(['"])WP_MAX_MEMORY_LIMIT\1\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT','\$2\$3')/ig" wp-config.php
  perl -i -pe "s/define\(\s*WP_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MEMORY_LIMIT','\$1\$2')/ig" wp-config.php
  perl -i -pe "s/define\(\s*WP_MAX_MEMORY_LIMIT\s*,\s*([0-9]+)\s*([MG])\s*\)/define('WP_MAX_MEMORY_LIMIT','\$1\$2')/ig" wp-config.php

  # Quote unquoted environment type values
  perl -i -pe "s/define\(\s*(['"])WP_ENVIRONMENT_TYPE\1\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE','\$2')/i" wp-config.php
  perl -i -pe "s/define\(\s*WP_ENVIRONMENT_TYPE\s*,\s*(development|staging|production)\s*\)/define('WP_ENVIRONMENT_TYPE','\$1')/i" wp-config.php

  php -l wp-config.php >/dev/null || { echo "wp-config.php still has a syntax error (see php -l)."; exit 1; }
fi

# ── Confirm WordPress loads (without plugins/themes)
wp core is-installed --skip-plugins --skip-themes >/dev/null 2>&1   || { echo "WP-CLI can't load WordPress (check path/db)."; exit 1; }

echo "== wp-config constants =="
# String constants (let WP-CLI add quotes)
wp config set WP_ENVIRONMENT_TYPE development --type=constant        2>/dev/null || true
wp config set WP_MEMORY_LIMIT      256M        --type=constant        2>/dev/null || true
# Booleans / ints (raw)
wp config set WP_DEBUG true        --type=constant --raw 2>/dev/null || true
wp config set WP_DEBUG_LOG true    --type=constant --raw 2>/dev/null || true
wp config set WP_DEBUG_DISPLAY false --type=constant --raw 2>/dev/null || true
wp config set SCRIPT_DEBUG true    --type=constant --raw 2>/dev/null || true
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
HOME_ID="$(ensure_page 'Home'    'home')"
ABOUT_ID="$(ensure_page 'About'   'about')"
BLOG_ID="$(ensure_page 'Blog'    'blog')"
CONTACT_ID="$(ensure_page 'Contact' 'contact')"
wp option update show_on_front 'page'
wp option update page_on_front "$HOME_ID"
wp option update page_for_posts "$BLOG_ID"

echo "== Content: delete defaults =="
HW_ID="$(wp post list --post_type=post --title='Hello world!' --format=ids)"; [ -z "$HW_ID" ] || wp post delete "$HW_ID" --force
SP_ID="$(wp post list --post_type=page --title='Sample Page'  --format=ids)"; [ -z "$SP_ID" ] || wp post delete "$SP_ID" --force

echo "== Plugins =="
wp plugin delete akismet hello 2>/dev/null || true
wp plugin install gutenberg create-block-theme query-monitor debug-bar user-switching regenerate-thumbnails wp-mail-logging --activate

echo "== Themes =="
wp theme activate twentytwentyfive || true
wp theme delete twentytwentyfour twentytwentythree 2>/dev/null || true

echo "== Language (English UK) =="
wp language core install  en_GB >/dev/null 2>&1 || true
wp language core activate en_GB >/dev/null 2>&1 || true
wp option  update WPLANG en_GB   >/dev/null 2>&1 || true
wp config  delete WPLANG         >/dev/null 2>&1 || wp config set WPLANG en_GB --type=constant >/dev/null 2>&1 || true
wp language plugin install --all en_GB >/dev/null 2>&1 || true
wp language theme  install --all en_GB >/dev/null 2>&1 || true
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
wp option update medium_size_w 900   ; wp option update medium_size_h 0
wp option update medium_large_size_w 1536 ; wp option update medium_large_size_h 0
wp option update large_size_w 1400   ; wp option update large_size_h 0
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

echo "== Finalize =="
wp rewrite flush

echo -e "
Bootstrap complete."
```

---

## 🔄 Updating
- Keep your canonical `bootstrap.sh` in GitHub; edit as your defaults evolve.
- Use the one-liner to always pull the newest version.

---

## 📜 License
MIT — free to copy, adapt, and share.
