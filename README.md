# Studio Starter Bootstrap

A handy script + MU-plugin combo to instantly configure a fresh **Studio by WordPress** site with your preferred development defaults.

---

## 🚀 Quick Start

### One-liner (recommended)

Run directly from GitHub to always use the latest version:

```bash
cd /path/to/your/studio-site
curl -sSL https://raw.githubusercontent.com/YOUR-USERNAME/YOUR-REPO/main/bootstrap.sh | bash
```

Replace `YOUR-USERNAME/YOUR-REPO` with your GitHub repo path. This will:

* Patch `wp-config.php` with debug constants.
* Apply your timezone, permalinks, and date/time formats.
* Create Home + Blog pages and set static front page.
* Delete default content.
* Install/activate your plugin set.
* Set media defaults.
* Disable comment notifications, pingbacks/trackbacks.
* Reset widgets.
* Create a menu and assign Home/Blog.
* Add a tiny MU-plugin to disable emoji + oEmbed scripts.

### Manual Run

1. Copy `bootstrap.sh` into your site root.
2. `chmod +x bootstrap.sh`
3. `./bootstrap.sh`

---

## 📦 What It Does

### 🔧 Config (`wp-config.php`)

* `WP_ENVIRONMENT_TYPE=development`
* `WP_DEBUG` on
* `WP_DEBUG_LOG` enabled
* `WP_DEBUG_DISPLAY` off
* `SCRIPT_DEBUG` on
* `DISALLOW_FILE_EDIT` on
* `WP_MEMORY_LIMIT=256M`
* `WP_DISABLE_FATAL_ERROR_HANDLER=true`
* `WP_POST_REVISIONS=10`

### 🌍 Options

* Timezone → `Europe/London`
* Permalink structure → `/%postname%/`
* Random tagline (8 random lowercase letters)
* Date format → `j F Y`
* Time format → `H:i`
* Discourage search engines → on

### 📰 Content

* Create Home + Blog pages
* Assign as front page + posts page
* Delete “Hello world!” + “Sample Page”

### 🔌 Plugins

* Deletes: Akismet, Hello Dolly
* Installs + activates:

  * Gutenberg
  * Query Monitor
  * Debug Bar
  * User Switching
  * Regenerate Thumbnails
  * WP Mail Logging

### 🎨 Themes

* Activates Twenty Twenty-Five
* Deletes Twenty Twenty-Three & Twenty Twenty-Four (if present)

### 💬 Discussion

* Disable email notifications
* Disable pingbacks/trackbacks
* Require moderation (no auto-approve)

### 🖼 Media

* Thumbnail → 150px
* Medium → 1024px
* Medium Large → 1536px
* Large → 2048px
* Default insert size → large

### 📑 Menus

* Creates Main Menu
* Adds Home + Blog
* Assigns to `primary` location if available

### 🗑 Widgets

* Clears all sidebars (no widgets)

### ✨ MU-plugin: `dev-tweaks.php`

* Disables emoji detection script
* Disables oEmbed discovery links and host JS

---

## 🔄 Updating

* Keep your canonical `bootstrap.sh` in GitHub.
* Update it as your defaults evolve.
* Use the one-liner to always pull the newest version.

---

## 🧩 Alfred Integration

* Save the one-liner as a snippet in Alfred (e.g., keyword `;wpboot`).
* Type `;wpboot` in your terminal → auto-pastes the curl command.
* You’ll always be a single keystroke away from a fully bootstrapped site.

---

## ⚠️ Notes

* Script is idempotent → safe to re-run; it just reapplies settings.
* If MU-plugin tweaks aren’t needed, delete `wp-content/mu-plugins/dev-tweaks.php`.
* Emoji cleanup may affect very old browsers (rare).
* Adjust plugin/theme list as your workflow changes.

---

## 📜 License

MIT — free to copy, adapt, and share.
