import Foundation

public enum VideoError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

public enum Timecode {
    public static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            guard !part.isEmpty, part.allSatisfy({ $0.isNumber || $0 == "." }),
                  let value = Double(part), value.isFinite, value >= 0,
                  (index == parts.count - 1 || value.rounded() == value),
                  (index == 0 || value < 60) else { return nil }
            total = total * 60 + value
        }
        return total.isFinite ? total : nil
    }

    public static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < 1e9 else { return "0:00" }
        let value = Int(seconds)
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    public static func editable(_ seconds: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds)
    }
}

public struct ClipRange: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public init(start: String, end: String, duration: Double?) throws {
        guard let a = Timecode.parse(start), let b = Timecode.parse(end), b > a else {
            throw VideoError.message("Enter a valid start and end time. The end must be after the start.")
        }
        if let duration, duration > 0, b > duration + 0.05 {
            throw VideoError.message("The segment ends after the video. Choose an earlier end time.")
        }
        self.start = a
        self.end = b
    }
    public var section: String { "*\(Timecode.editable(start))-\(Timecode.editable(end))" }
}

public enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case best = "Best available", hd = "1080p", preview = "720p"
    public var id: String { rawValue }
    public var selector: String {
        let height = self == .best ? "" : "[height<=?\(self == .hd ? 1080 : 720)]"
        // Prefer native Mac-compatible H.264 + AAC, then let FFmpeg convert a fallback.
        return "bv[vcodec^=avc1]\(height)+ba[ext=m4a]/b[ext=mp4][vcodec^=avc1]\(height)/bv\(height)+ba/b\(height)"
    }
}

public enum VideoCommands {
    public static func validateURL(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else {
            throw VideoError.message("Paste a valid http or https video URL.")
        }
        return trimmed
    }
    public static let common = ["--ignore-config", "--no-playlist", "--no-colors", "--newline", "--no-plugin-dirs", "--socket-timeout", "30", "--retries", "3"]
    public static func metadata(url: String) -> [String] {
        common + ["--skip-download", "--dump-single-json", "--", url]
    }
    public static func download(url: String, directory: URL, quality: VideoQuality, clip: ClipRange?, exact: Bool, token: String) -> [String] {
        var args = common + ["--no-simulate", "--format", quality.selector,
            "--merge-output-format", "mp4", "--recode-video", "mp4",
            "--postprocessor-args", "VideoConvertor+ffmpeg_o:-c:v libx264 -c:a aac",
            "--progress-template", "download:FRAME_PROGRESS:%(progress._percent_str)s",
            "--print", "after_move:FRAME_FILE:%(filepath)s",
            "--paths", directory.path,
            "--output", "%(title).140B [%(id)s] \(token).%(ext)s"]
        if let clip {
            args += ["--download-sections", clip.section]
            if exact { args += ["--force-keyframes-at-cuts"] }
        }
        return args + ["--", url]
    }
}

public struct VideoMetadata: Decodable, Sendable {
    public let title: String
    public let duration: Double?
    public let uploader: String?
    public let thumbnail: String?
    public let isLive: Bool?
    enum CodingKeys: String, CodingKey {
        case title, duration, uploader, thumbnail
        case isLive = "is_live"
    }
}

public enum ToolLocator {
    public static func find(_ name: String) -> URL? {
        let directories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }
    public static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        env["LC_ALL"] = "en_US.UTF-8"
        return env
    }
}
