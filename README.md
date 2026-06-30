# FileSizeScanner

**A fast, native macOS app for visualizing and analyzing disk space usage.**

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support%20this%20project-yellow?style=for-the-badge&logo=buymeacoffee)](https://buymeacoffee.com/romil66)

---

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-Free-green?style=flat-square)
![Version](https://img.shields.io/badge/Version-1.1.0-blue?style=flat-square)

---

## Features

- **Multiple Visualizations** — File tree, list view, pie chart, treemap, and file type breakdown
- **Fast Scanning** — Async directory enumeration with live progress; cancellable at any time
- **Smart Bar Visualization** — Square-root scale bars make size differences immediately visible
- **Largest Files** — Top 100 largest files with one-click Reveal in Finder or Move to Trash
- **File Type Analysis** — Aggregated breakdown by extension with size and count
- **Disk Usage Overview** — Ring chart with free/used/purgeable space and APFS volume info
- **Stale File Detection** — Identifies files not modified for 1–5+ years
- **Cloud Storage Skip** — Skips OneDrive, Dropbox, iCloud Drive etc. to avoid triggering sync
- **Full Disk Access** — Permission banner guides you through granting access for system folders
- **Dark & Light Mode** — Follows macOS appearance; switchable in toolbar
- **Localized** — English and German

---

## Download

👉 **[Download FileSizeScanner.zip](./FileSizeScanner.zip)**

Unzip, move `FileSizeScanner.app` to your `/Applications` folder, and launch.

> **First launch:** macOS will show an "unverified developer" warning.  
> Right-click the app → **Open** → click **Open** to confirm. This is only needed once.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

---

## Screenshots

| Overview | List View | Treemap |
|----------|-----------|---------|
| ![Overview](screenshots/overview.png) | ![List](screenshots/list.png) | ![Treemap](screenshots/treemap.png) |

---

## Usage

1. Launch FileSizeScanner
2. Select a folder or volume from the welcome screen
3. Wait for the scan to complete
4. Navigate through the tree or switch between visualization tabs
5. Click any folder to drill down; use Back/Forward to navigate history
6. Use **Edit Mode** to safely move files to Trash

---

## Privacy

FileSizeScanner reads your filesystem to compute sizes. It does **not** collect, transmit, or store any data. All processing happens entirely on your Mac.

---

## Support

If you find a bug or have a feature request, please [open an issue](../../issues).

---

## If you like this app, buy me a beer! 🍺

[![Buy Me A Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/romil66)
