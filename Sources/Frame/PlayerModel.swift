import SwiftUI
import AVKit
import UniformTypeIdentifiers
import FrameCore

struct SavedVideo: Identifiable, Codable {
    var id = UUID()
    let title: String
    let path: String
    let detail: String
    let date: Date
}

enum LoopMode: String, CaseIterable, Identifiable {
    case off = "Off", video = "Whole video", segment = "A–B segment"
    var id: String { rawValue }
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published var input = ""
    @Published var metadata: VideoMetadata?
    @Published var sourceURL: String?
    @Published var start = "0:00"
    @Published var end = "0:10"
    @Published var loop: LoopMode = .off
    @Published var quality: VideoQuality = .hd
    @Published var exactCuts = true
    @Published var segmentDownload = false
    @Published var loading = false
    @Published var downloading = false
    @Published var previewProgress: Double?
    @Published var downloadProgress: Double?
    @Published var status = "Your next great frame starts here."
    @Published var downloadStatus = ""
    @Published var error: String?
    @Published var currentTime = 0.0
    @Published var duration = 0.0
    @Published var hasPlayer = false
    @Published var isPlaying = false
    @Published var localTitle: String?
    @Published var saved: [SavedVideo] = []
    @Published var toolStatus = ""
    @Published var toolsReady = false
    @Published var destination: URL
    let player = AVPlayer()
    private var previewRunner: ProcessRunner?
    private var downloadRunner: ProcessRunner?
    private var previewTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var itemObservation: NSKeyValueObservation?
    private var loopSeeking = false
    private var previewDirectory: URL?
    private let historyURL: URL

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Frame", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        historyURL = support.appendingPathComponent("downloads.json")
        if let data = try? Data(contentsOf: historyURL), let entries = try? JSONDecoder().decode([SavedVideo].self, from: data) { saved = entries }
        if let path = UserDefaults.standard.string(forKey: "downloadFolder") {
            destination = URL(fileURLWithPath: path)
        } else {
            destination = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Frame", isDirectory: true)
        }
        refreshTools()
        if ProcessInfo.processInfo.arguments.contains("--silent-preview") { player.isMuted = true; player.volume = 0 }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor in
                guard let self, item === self.player.currentItem else { return }
                if self.loop == .video { self.seekAndPlay(0) }
                else if self.loop == .segment, let clip = self.clip { self.seekAndPlay(clip.start) }
            }
        }
    }

    var title: String { localTitle ?? metadata?.title ?? "Watch. Repeat. Keep." }
    var clip: ClipRange? { try? ClipRange(start: start, end: end, duration: effectiveDuration) }
    var effectiveDuration: Double? { duration > 0 ? duration : metadata?.duration }
    var clipError: String? {
        do { _ = try ClipRange(start: start, end: end, duration: effectiveDuration); return nil }
        catch { return error.localizedDescription }
    }

    func refreshTools() {
        let missing = ["yt-dlp", "ffmpeg", "deno"].filter { ToolLocator.find($0) == nil }
        toolsReady = !missing.contains("yt-dlp") && !missing.contains("ffmpeg")
        toolStatus = missing.isEmpty ? "Video tools ready" : "Missing: " + missing.joined(separator: ", ")
    }

    func load() {
        guard !loading else { return }
        do {
            let url = try VideoCommands.validateURL(input)
            guard let executable = ToolLocator.find("yt-dlp"), ToolLocator.find("ffmpeg") != nil else {
                throw VideoError.message("Install the video tools with: brew install yt-dlp ffmpeg deno. Then click Check tools.")
            }
            resetPlayer()
            metadata = nil
            localTitle = nil
            sourceURL = nil
            loop = .off
            error = nil
            loading = true
            previewProgress = nil
            status = "Reading video details…"
            let runner = ProcessRunner()
            previewRunner = runner
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Frame-\(UUID().uuidString)", isDirectory: true)
            previewDirectory = directory
            previewTask = Task {
                defer { loading = false; previewRunner = nil; previewTask = nil }
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let result = try await runner.run(executable: executable, arguments: VideoCommands.metadata(url: url))
                    try Task.checkCancellation()
                    let info = try JSONDecoder().decode(VideoMetadata.self, from: Data(result.output.utf8))
                    guard info.isLive != true else { throw VideoError.message("This video is live. Open a completed video to use preview, looping, and segment downloads.") }
                    metadata = info
                    sourceURL = url
                    start = "0:00"
                    end = Timecode.editable(min(info.duration ?? 10, 10))
                    status = "Preparing a 720p preview…"
                    let preview = try await runner.run(executable: executable, arguments: VideoCommands.download(url: url, directory: directory, quality: .preview, clip: nil, exact: false, token: "preview")) { [weak self] line in
                        guard let progress = Self.progress(line) else { return }
                        Task { @MainActor in self?.previewProgress = progress }
                    }
                    try Task.checkCancellation()
                    let file = try Self.outputFile(preview.output)
                    play(file)
                    status = "Preview ready · exports use your selected quality"
                } catch is CancellationError {
                    status = "Preview cancelled"
                    try? FileManager.default.removeItem(at: directory)
                } catch {
                    self.error = error.localizedDescription
                    status = "Couldn’t prepare this video"
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func cancelPreview() { previewTask?.cancel(); previewRunner?.cancel() }
    func cancelDownload() { downloadTask?.cancel(); downloadRunner?.cancel() }

    func download() {
        guard !downloading else { return }
        do {
            guard let url = sourceURL, let executable = ToolLocator.find("yt-dlp") else { throw VideoError.message("Load a video URL first.") }
            let range = segmentDownload ? try ClipRange(start: start, end: end, duration: effectiveDuration) : nil
            let selectedTitle = metadata?.title ?? "Video"
            let directory = destination
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let args = VideoCommands.download(url: url, directory: directory, quality: quality, clip: range, exact: exactCuts, token: String(UUID().uuidString.prefix(8)))
            let detail = range.map { "\(Timecode.format($0.start)) – \(Timecode.format($0.end))" } ?? "Full video"
            let runner = ProcessRunner()
            downloadRunner = runner
            downloading = true
            downloadProgress = nil
            downloadStatus = "Downloading \(detail.lowercased())…"
            error = nil
            downloadTask = Task {
                defer { downloading = false; downloadRunner = nil; downloadTask = nil }
                do {
                    let result = try await runner.run(executable: executable, arguments: args) { [weak self] line in
                        Task { @MainActor in
                            if let value = Self.progress(line) { self?.downloadProgress = value }
                            if line.hasPrefix("[Merger]") || line.hasPrefix("[VideoConvertor]") || line.hasPrefix("[VideoRemuxer]") {
                                self?.downloadStatus = "Finishing video…"
                                self?.downloadProgress = nil
                            }
                        }
                    }
                    try Task.checkCancellation()
                    let file = try Self.outputFile(result.output)
                    saved.insert(SavedVideo(title: selectedTitle, path: file.path, detail: detail, date: Date()), at: 0)
                    persistHistory()
                    downloadStatus = "Saved to \(directory.lastPathComponent)"
                    downloadProgress = 1
                } catch is CancellationError { downloadStatus = "Download cancelled · partial files may remain in the destination" }
                catch { self.error = error.localizedDescription; downloadStatus = "Download failed" }
            }
        } catch { self.error = error.localizedDescription }
    }

    nonisolated static func progress(_ line: String) -> Double? {
        guard line.hasPrefix("FRAME_PROGRESS:"), let value = Double(line.dropFirst("FRAME_PROGRESS:".count).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) else { return nil }
        return min(1, max(0, value / 100))
    }
    nonisolated static func outputFile(_ output: String) throws -> URL {
        guard let line = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("FRAME_FILE:") }) else {
            throw VideoError.message("The download completed without reporting a video file.")
        }
        let file = URL(fileURLWithPath: String(line.dropFirst("FRAME_FILE:".count)))
        guard FileManager.default.fileExists(atPath: file.path) else { throw VideoError.message("The completed video file could not be found.") }
        return file
    }

    func play(_ file: URL) {
        player.pause()
        let item = AVPlayerItem(url: file)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                if item.status == .failed {
                    self.error = item.error?.localizedDescription ?? "macOS couldn’t play this format. Try a different video."
                }
            }
        }
        player.replaceCurrentItem(with: item)
        hasPlayer = true
        currentTime = 0
        duration = 0
        if ProcessInfo.processInfo.arguments.contains("--silent-preview") { player.isMuted = true; player.volume = 0 }
        player.play()
    }

    func openSaved(_ video: SavedVideo) {
        guard !loading else { return }
        let file = URL(fileURLWithPath: video.path)
        guard FileManager.default.fileExists(atPath: file.path) else { error = "This file was moved or deleted. It was saved at \(video.path)."; return }
        resetPlayer()
        sourceURL = nil
        metadata = nil
        localTitle = video.title
        loop = .off
        start = "0:00"; end = "0:10"
        play(file)
        status = "Local video · \(video.detail)"
    }

    func openLocal() {
        guard !loading else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let file = panel.url else { return }
        openSaved(SavedVideo(title: file.deletingPathExtension().lastPathComponent, path: file.path, detail: "Local file", date: Date()))
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        panel.prompt = "Choose folder"
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
            UserDefaults.standard.set(url.path, forKey: "downloadFolder")
        }
    }

    func markStart() { start = Timecode.editable(currentTime) }
    func markEnd() { end = Timecode.editable(currentTime) }
    func togglePlayback() { player.rate == 0 ? player.play() : player.pause() }
    func seek(_ seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func previewClip() {
        guard let clip else { error = clipError; return }
        loop = .segment
        seekAndPlay(clip.start)
    }
    private func seekAndPlay(_ seconds: Double) {
        guard !loopSeeking else { return }
        loopSeeking = true
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                self.loopSeeking = false
                if finished { self.player.play() }
            }
        }
    }
    private func tick(_ time: Double) {
        if time.isFinite { currentTime = max(0, time) }
        isPlaying = player.rate > 0
        if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 { duration = seconds }
        if loop == .segment, isPlaying, let clip, (currentTime >= clip.end || currentTime < clip.start - 0.1) { seekAndPlay(clip.start) }
    }
    private func resetPlayer() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservation = nil
        hasPlayer = false
        duration = 0; currentTime = 0; loopSeeking = false
        if let previewDirectory { try? FileManager.default.removeItem(at: previewDirectory) }
        previewDirectory = nil
    }
    private func persistHistory() {
        do { try JSONEncoder().encode(saved).write(to: historyURL, options: .atomic) }
        catch { self.error = "The video was saved, but download history couldn’t be updated: \(error.localizedDescription)" }
    }
    func removeHistory(_ video: SavedVideo) { saved.removeAll { $0.id == video.id }; persistHistory() }
    func shutdown() {
        cancelPreview(); cancelDownload()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        if !loading, let previewDirectory { try? FileManager.default.removeItem(at: previewDirectory) }
    }
}
