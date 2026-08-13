# QuickMarkShot / 轻截

[中文](README.md) · [User Guide](docs/en/USER_GUIDE.md) · [Development](docs/en/DEVELOPMENT.md) · [Troubleshooting](docs/en/TROUBLESHOOTING.md)

## Overview

QuickMarkShot is a lightweight native macOS screenshot, quick annotation, and screen recording tool. It lives in the menu bar and uses system frameworks to capture, annotate, encode, and process cursor-follow zoom locally.

## Features

- `⌘⇧1` main-display screenshots and `⌘⇧2` region or window screenshots
- Immediate rectangle, ellipse, arrow, and freehand annotation
- Custom color and width, Shift constraints, undo, redo, clear, copy, and PNG save
- Open existing images for annotation
- `⌘⇧5` recording of a display, region, window, or application
- Optional system audio, cursor, and click indicators
- 1.5×, 1.8×, and 2.0× cursor-follow zoom with local post-processing
- MP4 (H.264 + AAC) output under `~/Movies/轻截录屏`
- `⌘⇧0` to hide or restore the menu bar item

## Advantages

- Native AppKit, ScreenCaptureKit, and AVFoundation implementation with no third-party runtime
- Capture and processing stay on the Mac; screenshots and recordings are not uploaded
- Screenshots preserve source resolution and flow directly into annotation
- Explicit recording-source selection and clear permission handling
- A focused menu bar entry point for screenshot, annotation, and recording

## Requirements and permissions

- macOS 15.0 or later
- Apple Silicon (arm64)
- Screen & System Audio Recording permission is required for capture; system-audio capture is managed by the same macOS permission area

## Install

Download `轻截-macOS.zip` from [Releases](https://github.com/lexaup/QuickMarkShot/releases), extract it, and move `轻截.app` to Applications. Approve the first launch under System Settings → Privacy & Security if blocked. Grant capture permission when prompted, then relaunch the app.

## Shortcuts

| Action | Shortcut |
|---|---|
| Main-display screenshot | `⌘⇧1` |
| Region/window screenshot | `⌘⇧2` |
| Start recording | `⌘⇧5` |
| Hide/restore menu bar item | `⌘⇧0` |

See the [User Guide](docs/en/USER_GUIDE.md) for annotation shortcuts and complete workflows.

## Privacy

QuickMarkShot has no capture upload or telemetry. Screenshots, recordings, and cursor-zoom post-processing remain local. Recordings are stored in the user's Movies directory by default.

## Build

```sh
git clone https://github.com/lexaup/QuickMarkShot.git
cd QuickMarkShot
./Scripts/verify.sh
```

The ZIP is written to `build/轻截-macOS.zip`. See [Development](docs/en/DEVELOPMENT.md).

## Version history

Verified source history includes v1.0, v2.0 Builds 2/3, and v2.1 Builds 4/5. Only the original final v2.1 Build 5 package was retained and attached to its Release; missing historical binaries were not fabricated. See [CHANGELOG](CHANGELOG.md).

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING](CONTRIBUTING.md), and use [SECURITY](SECURITY.md) for security reports.

## License

[MIT](LICENSE)
