# QuickMarkShot Development and Maintenance

## Environment and structure

Use an Apple Silicon Mac with macOS 15+ and Xcode Command Line Tools. `QuickMarkShot.swift` owns screenshots, annotation, menus, and shortcuts; `Recording.swift` owns ScreenCaptureKit sources and recording; `MouseZoom.swift` performs cursor-follow composition; `main.swift` is the entry point.

## Build, install, and verify

```sh
git clone https://github.com/lexaup/QuickMarkShot.git
cd QuickMarkShot
./build.sh
./install.sh
./Scripts/verify.sh
```

The build writes `build/轻截-macOS.zip` and uses ad-hoc signing. Automated verification covers compilation, archive, plist, version, arm64, signature, icon, and source contracts. It does not request TCC permission or prove interactive screenshot, audio, or window-selection behavior.

## Maintenance rules

- Capture changes require manual screenshot and all-four-source recording regression.
- Update Chinese and English docs plus CHANGELOG for user-visible changes.
- Never commit packages, recordings, private screenshots, or other captured content.
- Increment the marketing version and build in `Info.plist`.

## Release

Run verification and complete the permission and capture tests in the [Release Checklist](RELEASE_CHECKLIST.md). Create an annotated tag, build the ZIP, record SHA-256, attach it to the Release, and verify a public download.
