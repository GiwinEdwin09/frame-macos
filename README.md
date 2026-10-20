# Frame for Mac

A native SwiftUI + AVKit video player and downloader powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp) and FFmpeg.

## Run

Open **`dist/Frame.app`** in Finder, or run:

```sh
open dist/Frame.app
```

The app has been built for this Apple Silicon Mac. You can move it to Applications. It uses tools installed separately with Homebrew; it is not a self-contained or notarized distribution.

## Use

1. Paste a YouTube or other supported video URL and click **Load video**.
2. Frame reads the metadata and caches a preview at up to 720p before starting native playback. Long videos take longer to prepare and need temporary disk space. Export controls become available after metadata loads, so you can download a segment without waiting for the full preview.
3. Use the native controls to play, pause, scrub, change volume, enter full screen, or use picture in picture.
4. Choose **Whole video** in the Loop menu to repeat the entire video.
5. For an A–B loop, enter **Start** and **End**, or use the two **Use playhead** buttons. Click **Preview** to jump to the start and loop the selection.
6. Choose **Full video** or **Segment**, a quality, and a destination folder, then click **Download**.

Timestamps accept seconds (`90.5`), minutes (`1:30.5`), or hours (`1:02:30`). End must be later than start and within the known video duration. **Precise cuts** uses yt-dlp's `--force-keyframes-at-cuts` option; re-encoding takes longer but improves cut boundaries. With it off, boundaries can follow nearby keyframes. Encoded media still has frame-level timing limits.

Downloads default to `~/Downloads/Frame`. Download history persists across launches; play a saved file or reveal it in Finder from the list. Removing an entry from history does not delete its file. Cancelled exports can leave partial files in the selected folder.

**Open local video** plays files already on your Mac and supports both loop modes. Download/export controls apply to loaded web URLs, not local files.

## Requirements and rebuild

- macOS 14 or later.
- Apple Command Line Tools with Swift 5.9 or newer; full Xcode is optional.
- Homebrew tools:

```sh
brew install yt-dlp ffmpeg deno
./scripts/build-app.sh
```

The build script creates and ad-hoc signs `dist/Frame.app`. It compiles for the current Mac's architecture. Open `Package.swift` in Xcode to edit there, or use any editor and the build script.

Update the extraction tools when a website changes:

```sh
brew upgrade yt-dlp ffmpeg deno
```

Frame checks `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, and PATH, including when launched from Finder. Deno provides the JavaScript runtime used by yt-dlp for YouTube. No browser cookies or account credentials are read by Frame.

## Verification

Run the standalone checks (no XCTest or full Xcode required):

```sh
./scripts/check.sh
```

For a deterministic real download/segment test, serve an eight-second test video:

```sh
mkdir -p .build/fixtures
ffmpeg -y -f lavfi -i testsrc2=size=640x360:rate=30 -t 8 -c:v libx264 -pix_fmt yuv420p -movflags +faststart .build/fixtures/sample.mp4
python3 -m http.server 18765 --bind 127.0.0.1 --directory .build/fixtures
```

Then, in a second terminal:

```sh
FRAME_TEST_VIDEO_URL=http://127.0.0.1:18765/sample.mp4 ./scripts/check.sh
```

Checks cover timestamp and URL validation, segment bounds, literal process arguments, concurrent stdout/stderr handling, cancellation, metadata parsing, and (with the fixture) real full and segment downloads with FFprobe duration validation. Audio playback and audio correctness are not tested.

For silent manual UI verification:

```sh
open dist/Frame.app --args --silent-preview
```

## Scope

- Preview is downloaded before playback rather than streamed directly. Temporary previews are removed when replacing the loaded video or exiting normally after preparation. Interrupted app termination can leave temporary files for macOS to clean up.
- Downloads prefer H.264/AAC in MP4 for native compatibility, with fallback formats where necessary. The selected quality is a ceiling when the source reports its resolution; sources with unknown resolution are accepted. Some fallback codecs may not play on every Mac.
- Livestreams are not supported. Private, age-restricted, subscription, and DRM-protected media may not work. Website restrictions or changes can still make a public video unavailable.
- Use downloaded content in accordance with its permissions and applicable site terms.

## Source layout

- `Sources/Frame`: native interface and playback/download state.
- `Sources/FrameCore`: yt-dlp arguments, timestamps, metadata, tool discovery, and cancellable process execution.
- `Tests/FrameCoreTests`: executable checks runnable with Command Line Tools.
- `scripts`: app packaging and verification commands.
