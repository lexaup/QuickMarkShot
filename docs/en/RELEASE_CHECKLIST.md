# QuickMarkShot Release Checklist

- [ ] Clean worktree; version and build incremented
- [ ] `./Scripts/verify.sh` passes; ZIP has no Finder metadata
- [ ] Manually test main-display, region, and window screenshots plus Retina dimensions
- [ ] Manually test rectangle, ellipse, arrow, pen, color, width, undo/redo, copy, and save
- [ ] Manually test display, region, window, and application recording
- [ ] Manually test system audio, cursor, clicks, all three zoom levels, stop/save, and Finder reveal
- [ ] Manually test first permission grant, denial, and relaunch flow
- [ ] Manually test menu-bar hide and restore
- [ ] Synchronize Chinese/English docs and CHANGELOG
- [ ] Extract ZIP, verify version and strict signature, and record SHA-256
- [ ] Verify tag; upload Release, download publicly, and compare SHA-256
