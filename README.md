# Fremio

Fremio is a personal-use native iOS movie and TV show watching app built with SwiftUI. It pairs a clean Apple-style iPhone interface with dynamic stream resolution, multi-server fallback logic, and native Liquid Glass components.

---

## Features
- Native SwiftUI app shell targeting iOS 26.0+ and compiled with Swift 6.2.
- Native Apple Liquid Glass effect using `.glassEffect(in:)` and `GlassEffectContainer` APIs for light-reactive glassmorphism.
- Real-time metadata, popular titles, trending lists, and similar content recommendations powered directly by TMDB.
- Direct hardware-accelerated playback for MP4 and HLS streams using AVKit and AVPlayer.
- Automatic multi-server fallback: sequentially queries and retries Flux 1 (`mp4Data`), Flux 2 (`mkvV2Data`/`mkvData`), and Flux 3 (`mkvV3Data`) stream endpoints.
- Custom CDN bypass headers (`"Referer": "https://vidvault.ru/"`) configured directly on `AVURLAsset`.
- Continue Watching progress saved locally with a custom progress bar dashboard.
- Library screen with Watchlist and Favorites.
- GitHub Actions workflow that automatically compiles and packages an unsigned iOS IPA artifact using `xtool`.

---

## Current Limitations
- The IPA produced by GitHub Actions is unsigned. You must sign/sideload it before installing it on an iPhone.
- Real Apple Liquid Glass requires building with iOS 26.0+ SDK.
- Direct playback relies on stream availability from remote databases. If a stream is missing from all three servers, the player returns a custom *"not found"* prompt.

---

## Repository Layout
```
.
├── .github/workflows/      # GitHub Actions build workflow
├── Sources/                # Native SwiftUI source code
│   └── Fremio/
│       ├── Components/     # Visual buttons, cards, tab bar
│       ├── Helpers/        # Haptics, metadata service, stream resolver
│       └── Views/          # Home, search, player, settings, library views
├── Package.swift           # Swift Package Manager manifest
└── README.md               # Documentation
```

---

## Building the Native iOS App
Windows cannot compile or sign native iOS apps locally. Use one of these options:
- A Mac with Xcode.
- A cloud Mac.
- GitHub Actions for unsigned build artifacts.

### Build with GitHub Actions
The repository includes `.github/workflows/build-ipa.yml` which automatically:
- Installs the `xtool` Darwin Swift SDK.
- Builds the app for iPhone using Xcode.
- Packages an unsigned IPA artifact.

To get your IPA:
1. Open the **Actions** tab on your GitHub repository.
2. Select the latest workflow run.
3. Download the artifact named `Fremio-unsigned-ipa`.

### Build with xtool on macOS
1. Install `xtool`:
   ```bash
   brew install xtool-org/tap/xtool
   ```
2. Build the unsigned IPA:
   ```bash
   xtool dev build --ipa --configuration release
   ```

---

## Signing and Sideloading
The GitHub Action artifact is unsigned and cannot be installed directly on an iPhone without signing. 

Recommended installation paths:
- **TrollStore** (Recommended for unsigned IPAs on supported iOS versions).
- **AltStore / Sideloadly** (For developer account/free Apple ID personal signing).
- **MapleSign / Signulous** (Or other third-party certificate signing services).

---

## Development Notes
The native app uses:
- SwiftUI for the entire visual shell.
- AVKit / AVPlayer for direct stream decoding.
- URLSession for TMDB metadata query logic and VidVault API calls.
