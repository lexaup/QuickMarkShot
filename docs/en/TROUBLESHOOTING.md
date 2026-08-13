# QuickMarkShot Troubleshooting

## Capture fails or the source list is empty

Allow QuickMarkShot under System Settings → Privacy & Security → Screen & System Audio Recording, then quit completely and relaunch. Changing the app, signature, or installation location can cause macOS to treat it as a new permission identity and prompt again.

## No system audio

Enable system audio in recording options and confirm Screen & System Audio Recording permission. Not every source is guaranteed to expose audio in every system state.

## Cursor-zoom processing fails

QuickMarkShot attempts to retain the unprocessed raw MP4 and displays the error. Check free disk space and output-folder writability, then continue with the raw file.

## The menu bar item disappeared

Press `⌘⇧0`. If another app owns the shortcut, quit the conflicting app and retry or relaunch QuickMarkShot.

## macOS blocks the first launch

Confirm the app came from this repository's Release, then choose Open Anyway under System Settings → Privacy & Security. Public packages are ad-hoc signed and not notarized.

## Cannot find a recording

The default folder is `~/Movies/轻截录屏`; it can also be opened from the menu bar menu.

## Reset screen-recording permission

Only when the permission record is genuinely broken and you accept revoking access, run `tccutil reset ScreenCapture local.codex.quickmarkshot`, then authorize again and relaunch.
