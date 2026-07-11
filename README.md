# Fremio 🎬

Fremio is a premium, lightweight, native iOS movie and TV show streaming client. Built using **Swift 6.2** and targeting **iOS 26.0+**, it utilizes Apple's native **Liquid Glass** effect for a high-end, light-reactive visual experience. 

Fremio communicates directly with TMDB for rich metadata and parses streaming endpoints dynamically without the need for an external proxy server or backend database.

---

## ✨ Features

* **Native SwiftUI & iOS 26 Liquid Glass:** Stunning glassmorphism UI leveraging Apple's native `.glassEffect(in:)` and `GlassEffectContainer` APIs.
* **Direct High-Quality Streaming:** Feeds raw video streams directly into Apple's hardware-accelerated `AVPlayer`.
* **Automatic Multi-Server Fallback:** Automatically queries and retries multiple servers in sequence when a title is requested:
  $$\text{Flux 1 (mp4Data)} \longrightarrow \text{Flux 2 (mkvV2Data)} \longrightarrow \text{Flux 3 (mkvV3Data)}$$
* **Smart Watch Progress:** Tracks and saves playback positions locally, rendering a beautiful custom progress bar under the **Continue Watching** dashboard.
* **Recommendations Engine:** Shows customized "You May Also Like" carousels based on similar TMDB genres.
* **Local Playlists:** Quick in-app Watchlists and Favorites stored securely in `UserDefaults`.

---

## 🛠️ How It Works

1. **Metadata Retrieval:** When you search or browse a title, Fremio fetches real-time details from **The Movie Database (TMDB)**. Responses and image assets are cached locally in the app's cache directory.
2. **Stream Resolution:** When you tap **Play**, the app generates a secure request token and calls the `vidvault.ru/api/download-proxy` endpoint.
3. **Fallback Loop:** The resolver scans Flux 1. If no direct streams are available, it retries on Flux 2, and then Flux 3. If all fail, the player displays a custom prompt: *"not found, please wait a little more for our team to put it on here."*
4. **Proxy Playback:** Once a stream is found, its URL is encoded and routed through a fast gateway (`https://vlaq11.site/`) using custom HTTP Referer and User-Agent headers to bypass CDN blocks.

---

## 🚀 Setup & Installation Guide

Fremio is configured to build as an unsigned `.ipa` automatically on every commit via GitHub Actions.

### Method 1: Sideloading via GitHub Actions (easiest)
1. Go to your public GitHub repository at [https://github.com/edfwasd1234/Fermio](https://github.com/edfwasd1234/Fermio).
2. Click on the **Actions** tab.
3. Select the latest workflow run.
4. Scroll down to the **Artifacts** section and download the `Fremio-unsigned-ipa` zip file.
5. Extract the `.ipa` and install it onto your iOS device using **TrollStore, AltStore, Sideloadly, or Esign**.

### Method 2: Local Compilation (macOS or WSL)
Fremio uses the `xtool` Swift compiler toolchain to build fast without complex Xcode project overhead.

1. Install `xtool` CLI using Homebrew:
   ```bash
   brew install xtool-org/tap/xtool
   ```
2. Build the unsigned `.ipa` bundle in Release configuration:
   ```bash
   xtool dev build --ipa --configuration release
   ```
3. Retrieve your finished `.ipa` from the output directory!
