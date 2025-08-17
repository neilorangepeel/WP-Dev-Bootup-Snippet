# Studio Starter Bootstrap

A handy script + MU-plugin combo to instantly configure a fresh **Studio by WordPress** site with your preferred development defaults — optimised for **block themes**.

---

## 🚀 Quick Start

### One-liner (recommended)
Run directly from GitHub to always use the latest version:

```bash
cd /path/to/your/studio-site
curl -sSL https://raw.githubusercontent.com/YOUR-USERNAME/YOUR-REPO/main/bootstrap.sh | bash
```

Replace `YOUR-USERNAME/YOUR-REPO` with your GitHub repo path. This will:

- Patch `wp-config.php` (debug constants, memory, environment) and **self-heal** common mistakes.
- Apply timezone, permalinks, date/time formats, and set **site language to English (UK)**.
- Create **Home**, **About**, **Blog**, **Contact** pages and set a static front page.
- Delete default content (`Hello world!`, `Sample Page`).
- Create **categories**, **tags**, and **10 starter posts** with random assignments + featured image placeholders.
- Install/activate your plugin set (Gutenberg, Create Block Theme, Query Monitor, etc.).
- Set **block-theme friendly media sizes**.
- Disable comment notifications, pingbacks/trackbacks.
- Set all users’ **Admin Color Scheme** to **Modern**.
- Add a tiny MU-plugin to disable **emoji** and **oEmbed** extras.
- Print total **execution time**.

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
- Site language → **English (UK)** (`en_GB`)
- Timezone → `Europe/London`
- Permalinks → `/%postname%/`
- Tagline → `'Just another site'`
- Date format → `j F Y` · Time format → `H:i`
- Discourage search engines (dev/staging)

### 📰 Content
- Creates **Home**, **About**, **Blog**, **Contact** pages
- Sets static front page + posts page
- Removes “Hello world!” + “Sample Page”
- Adds 5 categories + 10 tags
- Creates **10 posts** (draft, scheduled, published mix)
  - Random category + 2 random tags each
  - 2-paragraph generic content
  - Auto-generated 1600×900 coloured placeholder thumbnails
  - Excerpts auto-set

### 🔌 Plugins
- Deletes: Akismet, Hello Dolly
- Installs + activates:
  - Gutenberg · Create Block Theme · Query Monitor · Debug Bar · User Switching · Regenerate Thumbnails · WP Mail Logging

### 🎨 Themes
- Activates **Twenty Twenty-Five**
- Deletes older default themes

### 💬 Discussion
- Turns off email notifications
- Disables pingbacks/trackbacks
- Requires moderation (no auto-approve)

### 🖼 Media (block-theme friendly)
- **Thumbnail**: 320 × 320 (cropped)
- **Medium**: 900 × auto (height 0)
- **Medium Large**: 1536 × auto
- **Large**: 1400 × auto
- Default insert size: **large**

### 🎛 Admin Color Scheme
- Sets all users’ `admin_color` to **modern**

### ✨ MU-plugin: `dev-tweaks.php`
- Disables emoji detection script
- Disables oEmbed discovery and host JS

---

## 🧩 Alfred integration
- Save the one-liner as a snippet in Alfred (e.g., keyword `;wpboot`).
- Type `;wpboot` in your terminal → it pastes the curl command.

---

## 🧪 Verify (optional)

```bash
wp config get WP_ENVIRONMENT_TYPE --type=constant
wp config get WP_MEMORY_LIMIT     --type=constant
wp language core list --status=active   # should show en_GB active
wp option get WPLANG                    # should be en_GB
wp option get permalink_structure
wp option get timezone_string
wp plugin list --status=active
wp post list --post_type=post --format=table --fields=ID,post_title,post_status
```

---

## 📜 Reference: `bootstrap.sh`

> The script is short, clean, and prints elapsed execution time.

```bash
#!/usr/bin/env bash
set -euo pipefail
START_TIME=$(date +%s)
wpq(){ wp --skip-plugins --skip-themes "$@"; }

# ── Sanity
[ -f wp-config.php ] || { echo "wp-config.php not found"; exit 1; }
php -l wp-config.php >/dev/null 2>&1 || { echo "wp-config.php has syntax errors"; exit 1; }
wpq core is-installed >/dev/null 2>&1 || { echo "WordPress not loaded"; exit 1; }

# ── Config
wpq config set WP_ENVIRONMENT_TYPE development --type=constant 2>/dev/null || true
wpq config set WP_MEMORY_LIMIT 256M --type=constant 2>/dev/null || true
wpq config set WP_DEBUG true --type=constant --raw 2>/dev/null || true
wpq config set WP_DEBUG_LOG true --type=constant --raw 2>/dev/null || true
wpq config set WP_DEBUG_DISPLAY false --type=constant --raw 2>/dev/null || true
wpq config set SCRIPT_DEBUG true --type=constant --raw 2>/dev/null || true
wpq config set DISALLOW_FILE_EDIT true --type=constant --raw 2>/dev/null || true
wpq config set WP_DISABLE_FATAL_ERROR_HANDLER true --type=constant --raw 2>/dev/null || true
wpq config set WP_POST_REVISIONS 10 --type=constant --raw 2>/dev/null || true

# ── Main site setup + content
wp eval-file - <<'PHP'
<?php
// (trimmed for README brevity – full script in repo)
// Creates pages, deletes defaults, sets categories/tags,
// makes 10 posts with thumbnails, applies options.
PHP

# ── MU-plugin
mkdir -p wp-content/mu-plugins
cat > wp-content/mu-plugins/dev-tweaks.php <<'PHP'
<?php
add_action('init', function () {
  remove_action('wp_head','print_emoji_detection_script',7);
  remove_action('wp_head','wp_oembed_add_discovery_links');
});
PHP

# ── Plugins & themes
wp plugin delete akismet hello 2>/dev/null || true
wp plugin install gutenberg create-block-theme query-monitor debug-bar user-switching regenerate-thumbnails wp-mail-logging --activate
wp theme activate twentytwentyfive || true
wp theme delete twentytwentyfour twentytwentythree 2>/dev/null || true
wp rewrite flush

# ── Timing
END_TIME=$(date +%s); ELAPSED=$((END_TIME-START_TIME))
printf "\nBootstrap complete in %dm %ds\n" $((ELAPSED/60)) $((ELAPSED%60))
```

---

## 🔄 Updating
- Keep `bootstrap.sh` in your GitHub repo.
- Use the one-liner to always fetch the latest.

---

## 📜 License
MIT — free to copy, adapt, and share.
