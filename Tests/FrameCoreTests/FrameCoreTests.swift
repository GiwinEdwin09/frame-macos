import Foundation
import FrameCore

/// Runs with Command Line Tools alone; XCTest requires the full Xcode installation.
@main
struct FrameChecks {
    static var passed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw VideoError.message("FAIL: \(message)") }
        passed += 1
    }
    static func rejects(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { passed += 1; return }
        throw VideoError.message("FAIL: \(message)")
    }
    static func main() async throws {
        try check(Timecode.parse("1:02:03.5") == 3723.5, "hour timestamp")
        try check(Timecode.parse(" 02:30 ") == 150, "minute timestamp")
        try check(Timecode.parse("90.25") == 90.25, "decimal seconds")
        for invalid in ["", "1:60", "1::3", "-1", "NaN", "inf", "1:2:3:4", "1.5:10", "1e3", ":10"] {
            try check(Timecode.parse(invalid) == nil, "reject \(invalid)")
        }
        try check(Timecode.format(3723) == "1:02:03", "hour formatting")
        try check(Timecode.format(65) == "1:05", "minute formatting")
        try check(Timecode.format(.nan) == "0:00", "nonfinite formatting")
        try check(Timecode.editable(1.234) == "1.234", "decimal editing")
        let clip = try ClipRange(start: "1:02.5", end: "2:00", duration: 120)
        try check(clip.section == "*62.500-120.000", "section expression")
        try rejects("zero-length range") { _ = try ClipRange(start: "10", end: "10", duration: nil) }
        try rejects("reversed range") { _ = try ClipRange(start: "20", end: "10", duration: nil) }
        try rejects("out of bounds") { _ = try ClipRange(start: "0", end: "121", duration: 120) }
        let cleanURL = try VideoCommands.validateURL(" https://example.com/watch?v=a&list=b ")
        try check(cleanURL == "https://example.com/watch?v=a&list=b", "trim URL")
        for invalid in ["--exec=evil", "file:///etc/passwd", "https://", "video", "ftp://example.com/a"] {
            try rejects("invalid URL \(invalid)") { _ = try VideoCommands.validateURL(invalid) }
        }
        let url = "https://example.com/watch?v=$(touch%20oops)&list=1"
        let args = VideoCommands.download(url: url, directory: URL(fileURLWithPath: "/tmp/has spaces"), quality: .hd,
            clip: try ClipRange(start: "5.25", end: "10", duration: 20), exact: true, token: "unique")
        try check(Array(args.suffix(2)) == ["--", url], "literal URL argument")
        for argument in ["*5.250-10.000", "--force-keyframes-at-cuts", "/tmp/has spaces", "--ignore-config", "--no-playlist"] {
            try check(args.contains(argument), "argument \(argument)")
        }
        let full = VideoCommands.download(url: url, directory: URL(fileURLWithPath: "/tmp"), quality: .best, clip: nil, exact: true, token: "id")
        try check(!full.contains("--download-sections") && !full.contains("--force-keyframes-at-cuts"), "full download is not trimmed")
        let metadata = try JSONDecoder().decode(VideoMetadata.self, from: Data(#"{"title":"Demo","duration":8.2,"is_live":false}"#.utf8))
        try check(metadata.duration == 8.2 && metadata.uploader == nil && metadata.isLive == false, "optional metadata")
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "i=0; while [ $i -lt 6000 ]; do echo stdout; echo stderr >&2; i=$((i+1)); done"])
        try check(result.output.components(separatedBy: "stdout").count - 1 == 6000, "drain stdout")
        try check(result.diagnostics.components(separatedBy: "stderr").count - 1 == 6000, "drain stderr")
        do {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo specific-failure >&2; exit 3"])
            throw VideoError.message("Expected subprocess failure")
        } catch { try check(error.localizedDescription.contains("specific-failure"), "stderr error reporting") }
        let cancelled = ProcessRunner()
        cancelled.cancel()
        do {
            _ = try await cancelled.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["should not run"])
            throw VideoError.message("Expected cancellation")
        } catch { try check(error is CancellationError, "cancel before launch") }
        let runner = ProcessRunner()
        let task = Task { try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"]) }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        do { _ = try await task.value; throw VideoError.message("Expected cancellation") }
        catch { try check(error is CancellationError, "cancel running process") }
        if let testURL = ProcessInfo.processInfo.environment["FRAME_TEST_VIDEO_URL"] { try await integration(testURL) }
        print("PASS: \(passed) checks. No audio playback or audio validation performed.")
    }

    static func integration(_ url: String) async throws {
        guard let ytdlp = ToolLocator.find("yt-dlp"), let ffprobe = ToolLocator.find("ffprobe") else { throw VideoError.message("Missing integration tools") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FrameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let info = try await ProcessRunner().run(executable: ytdlp, arguments: VideoCommands.metadata(url: url))
        let metadata = try JSONDecoder().decode(VideoMetadata.self, from: Data(info.output.utf8))
        try check(!metadata.title.isEmpty, "real metadata extraction")
        for (token, range, expected) in [("full", nil as ClipRange?, 8.0), ("clip", try ClipRange(start: "2", end: "5", duration: 8), 3.0)] {
            let result = try await ProcessRunner().run(executable: ytdlp, arguments: VideoCommands.download(url: url, directory: directory, quality: .hd, clip: range, exact: true, token: token))
            guard let line = result.output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("FRAME_FILE:") }) else { throw VideoError.message("No exported path") }
            let path = String(line.dropFirst("FRAME_FILE:".count))
            try check(FileManager.default.fileExists(atPath: path), "\(token) file exists")
            let probe = try await ProcessRunner().run(executable: ffprobe, arguments: ["-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path])
            guard let duration = Double(probe.output.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw VideoError.message("No duration") }
            try check(abs(duration - expected) < 0.2, "\(token) duration: \(duration)")
        }
    }
}
