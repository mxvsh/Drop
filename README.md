# Drop

Convert, compress and keep files without leaving the drag.

Drop is a menu bar app for macOS. Start dragging any file, hold **⌥ Option**, and a small panel appears next to the cursor with actions that fit that file. Drop it on one and the result is saved next to the original, ready to drag on into Slack, Mail, Figma or wherever it was going.

Everything runs on your Mac. Nothing is uploaded.

## What it does

Drop looks at what you're dragging and only offers what makes sense. A format you already have isn't offered again.

| Files | Convert to | Tools |
|---|---|---|
| Images | PNG, JPEG, HEIC, WebP, ICNS, ICO, PDF | Compress, Resize, Remove background, Copy text (OCR), Strip metadata |
| PDFs | PNG (one per page) | Merge, Compress, Copy text |
| Videos | MP4, GIF | Compress, Extract audio |
| Audio | M4A | |
| Zip archives | | Unzip |
| Anything | | Zip, Copy path, Copy as Base64, SHA-256 checksum |

- **Asks when it matters.** Resize, Compress and GIF open a small form after the drop: size in percent or pixels with a proportion lock, quality, resolution, frame rate. Return confirms, Esc cancels, and the form remembers your last choice.
- **Shelf.** Drop files on the Shelf to park them, then drag them out later. Open it any time from the menu bar.
- **Results you can use straight away.** Drag the result out of the panel into any app, show it in Finder, or copy it. Size savings are shown when an action makes files smaller.

## Using it

1. Start dragging a file from Finder, the desktop, Mail or any other app.
2. Hold **⌥ Option**. The panel appears beside the cursor and stays open after you let go of the key.
3. Drop on an action. Hovering a tile shows what it does in the status line; hovering **More** reveals the rest.

The trigger can be changed to ⌃, ⌘, ⇧ or Fn, or to a quick shake of the cursor, in **Settings → General**. Finder already uses Option for "copy" while dragging; since the panel stays open once revealed, release the key before dropping somewhere else.

### Settings

- **General:** trigger key, shake to reveal, open at login, pause.
- **Output:** save next to the original, to Downloads or to a custom folder; keep originals or move them to the Trash; copy results to the clipboard; reveal in Finder.
- **Actions:** turn off any action you never use.

## Requirements

- macOS 15 Sequoia or later. On macOS 26 the panel uses Liquid Glass; earlier versions use a vibrant material.
- Xcode 26 or later to build.

Drop needs no Accessibility, Input Monitoring or Screen Recording permission.

## Building

```sh
make debug   # build and launch the Debug app ("Drop Debug", its own bundle ID)
make prod    # build and launch a Release build
make kill    # quit a running copy
make clean   # remove build output
```

Or open `Drop.xcodeproj` and run the **Drop** scheme. The only dependency is [libwebp](https://github.com/SDWebImage/libwebp-Xcode), pulled in by Swift Package Manager.

## How it works

- **Spotting a drag.** A global mouse-down monitor starts a short poll that runs only while the button is held. It watches the drag pasteboard for file URLs and checks the trigger key or a shake. No special permission is needed for any of this.
- **The panel.** A borderless, non-activating `NSPanel`, so the app you're dragging from keeps focus. Its SwiftUI content is measured before it appears so it opens at the right size, top edge level with the cursor, flipped to the left near the screen edge.
- **The work.** Native frameworks off the main thread: ImageIO and Core Graphics for images, libwebp for WebP encoding, `iconutil` for ICNS, Vision for background removal and text recognition, PDFKit for PDFs, AVFoundation for video and audio, `ditto` for archives. Output names never overwrite an existing file; `photo.png` becomes `photo 2.png` if needed.
- **No sandbox.** Writing results next to the original requires access to that folder, so the app sandbox is off. The hardened runtime stays on, as notarization requires.

## Project layout

```
Drop/
  App/          Entry point, app delegate, menu bar item
  Core/         Settings, drag detection, file type detection, output naming, Shelf
  Actions/      The action model and the catalog of every action
  Engines/      Image, WebP, PDF, media, Vision and file work
  Panel/        The floating panel, its controller, views and action forms
  Settings/     Settings window and panes
  Onboarding/   First-run welcome window
```

To add an action, add an `ActionSpec` to `Actions/ActionCatalog.swift`: its labels, when it's available, and the async work it runs. It appears in the panel and in Settings automatically. Give it a `configuration` to ask for values first.

### Debugging without dragging

Debug builds listen for a distributed notification that opens the panel for given files, which helps when checking layout from a script:

```swift
DistributedNotificationCenter.default().postNotificationName(
    .init("com.monawwar.Drop.debugReveal"),
    object: ["/path/to/a.png", "/path/to/b.pdf"].joined(separator: "\n"),
    userInfo: nil, deliverImmediately: true
)
```

## Not yet

- Signed and notarized DMG releases with Sparkle updates through GitHub Actions.
- An app icon.
- Drags that hand over a promise of a file rather than a real one, such as images dragged from Photos or Safari.
- Lossy PNG compression (convert to WebP or JPEG for now).
