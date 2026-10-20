import SwiftUI
import AVKit
import FrameCore

@main
struct FrameApp: App {
    @StateObject private var model = PlayerModel()
    var body: some Scene {
        Window("Frame", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 1060, minHeight: 740)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.shutdown() }
        }
        .defaultSize(width: 1280, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video File…") { model.openLocal() }.keyboardShortcut("o")
            }
        }
    }
}

private let accent = Color(red: 0.72, green: 0.94, blue: 0.43)
private let surface = Color(red: 0.095, green: 0.105, blue: 0.115)

struct ContentView: View {
    @ObservedObject var model: PlayerModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 22) {
                header
                urlBar
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        player
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.title).font(.title3.weight(.semibold)).lineLimit(2).textSelection(.enabled)
                                Text(model.metadata?.uploader ?? (model.hasPlayer ? "Local playback" : "A little space for your favorite videos."))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let duration = model.effectiveDuration { Text(Timecode.format(duration)).monospacedDigit().font(.caption).padding(7).background(.white.opacity(0.06), in: Capsule()) }
                        }
                        loopControls
                    }
                    inspector.frame(width: 260)
                }
                library
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Circle().fill(model.toolsReady ? accent : .orange).frame(width: 5, height: 5)
                    Text(model.status).lineLimit(1)
                    Spacer()
                    Text("POWERED BY YT-DLP").tracking(1.5).font(.system(size: 9, weight: .medium))
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
        .background(Color(red: 0.055, green: 0.065, blue: 0.075))
        .tint(accent)
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Copy details") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.error ?? "", forType: .string); model.error = nil }
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image(systemName: "play.square.stack.fill").font(.system(size: 26)).foregroundStyle(accent)
                Text("frame").font(.system(size: 28, weight: .bold, design: .rounded))
            }.padding(.top, 20)
            VStack(alignment: .leading, spacing: 10) {
                Text("WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary).padding(.bottom, 4)
                Label("Video studio", systemImage: "play.rectangle").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                Button { model.openLocal() } label: { Label("Open local video", systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.loading)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "repeat").font(.title2).foregroundStyle(accent)
                Text("Stay in the moment.").font(.system(size: 13, weight: .semibold))
                Text("Loop a favorite scene.\nKeep just the part you need.").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text(model.toolStatus).font(.caption2).foregroundStyle(.secondary)
                Button("Check tools") { model.refreshTools() }.buttonStyle(.link).font(.caption)
                if !model.toolsReady {
                    Text("brew install yt-dlp ffmpeg deno").font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                }
            }
            Text("FRAME FOR MAC  /  1.0").font(.system(size: 9)).tracking(1.5).foregroundStyle(.tertiary)
        }.padding(20).frame(width: 180).background(.white.opacity(0.018))
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Video studio").font(.system(size: 27, weight: .semibold))
                Text("Watch it. Loop it. Make it yours.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Label("ON YOUR MAC", systemImage: "desktopcomputer").font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(.secondary)
        }
    }
    private var urlBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "link").foregroundStyle(.secondary)
            TextField("Paste a YouTube or video URL…", text: $model.input).textFieldStyle(.plain).onSubmit { model.load() }.disabled(model.loading)
                .accessibilityLabel("Video URL")
            if model.loading {
                Button("Cancel") { model.cancelPreview() }.buttonStyle(.borderless)
            } else {
                Button { model.load() } label: { Label("Load video", systemImage: "arrow.right").labelStyle(.titleAndIcon).padding(.horizontal, 6) }
                    .buttonStyle(PrimaryButtonStyle()).disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(12).background(surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    }
    private var player: some View {
        ZStack {
            Color.black
            if model.hasPlayer {
                NativePlayer(player: model.player)
            } else {
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22).fill(accent.opacity(0.08)).frame(width: 82, height: 82).rotationEffect(.degrees(-9))
                        Image(systemName: model.loading ? "arrow.down.circle" : "play.fill").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
                    }
                    Text(model.loading ? "Getting your video ready" : "Give a good video your full attention.").font(.system(size: 17, weight: .medium))
                    Text(model.loading ? model.status : "Paste a link above, or open a video from your Mac.").font(.caption).foregroundStyle(.secondary)
                    if model.loading {
                        if let progress = model.previewProgress { ProgressView(value: progress).frame(width: 220) }
                        else { ProgressView().controlSize(.small) }
                        Text("A 720p preview is cached before playback.").font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        HStack(spacing: 22) {
                            Label("Native playback", systemImage: "play.rectangle")
                            Label("A–B looping", systemImage: "repeat")
                            Label("Precise clips", systemImage: "scissors")
                        }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 6)
                    }
                }.padding(20)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08)))
    }
    private var loopControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "repeat").foregroundStyle(model.loop == .off ? Color.secondary : accent)
            Picker("Loop", selection: $model.loop) {
                ForEach(LoopMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }.labelsHidden().frame(width: 145).disabled(!model.hasPlayer)
            Spacer()
            Text("\(Timecode.format(model.currentTime)) / \(Timecode.format(model.duration))").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }.padding(11).background(surface, in: RoundedRectangle(cornerRadius: 10))
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "scissors").foregroundStyle(accent)
                Text("Make the cut").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            Text("Pick the moment worth keeping.").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 12) {
                timeField("START", text: $model.start, mark: model.markStart)
                timeField("END", text: $model.end, mark: model.markEnd)
            }
            HStack {
                if let clip = model.clip {
                    Text("\(Timecode.format(clip.end - clip.start)) selected").font(.caption).foregroundStyle(accent)
                } else { Text("Check timestamps").font(.caption).foregroundStyle(.orange) }
                Spacer()
                Button { model.previewClip() } label: { Image(systemName: "play.circle"); Text("Preview") }.buttonStyle(.borderless).disabled(!model.hasPlayer || model.clip == nil)
            }
            if model.clip == nil {
                Text(model.clipError ?? "").font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Picker("Save", selection: $model.segmentDownload) {
                Text("Full video").tag(false)
                Text("Segment").tag(true)
            }.pickerStyle(.segmented)
            Picker("Quality", selection: $model.quality) {
                ForEach(VideoQuality.allCases) { quality in Text(quality.rawValue).tag(quality) }
            }.font(.caption)
            if model.segmentDownload {
                Toggle("Precise cuts", isOn: $model.exactCuts).font(.caption)
                Text("Re-encodes at the cut points. Slower, with cleaner segment boundaries.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button { model.chooseDestination() } label: {
                HStack {
                    Image(systemName: "folder")
                    Text(model.destination.lastPathComponent).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }.font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.plain).help(model.destination.path)
            Button { model.download() } label: {
                Label(model.segmentDownload ? "Download segment" : "Download video", systemImage: "arrow.down.to.line")
                    .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
            }.buttonStyle(PrimaryButtonStyle())
                .disabled(model.sourceURL == nil || model.downloading || (model.segmentDownload && model.clip == nil))
            if model.downloading {
                if let progress = model.downloadProgress { ProgressView(value: progress) }
                else { ProgressView().controlSize(.small) }
                HStack {
                    Text(model.downloadStatus).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { model.cancelDownload() }.buttonStyle(.borderless).font(.caption)
                }
            } else if !model.downloadStatus.isEmpty {
                Text(model.downloadStatus).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(18).background(surface, in: RoundedRectangle(cornerRadius: 14))
    }
    private func timeField(_ label: String, text: Binding<String>, mark: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Button("Use playhead", action: mark).font(.system(size: 10)).buttonStyle(.borderless).disabled(!model.hasPlayer)
            }
            TextField("0:00", text: text).font(.system(size: 20, weight: .medium, design: .monospaced)).textFieldStyle(.plain)
                .padding(10).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("\(label.lowercased()) time")
        }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your downloads").font(.system(size: 14, weight: .semibold))
                Text("\(model.saved.count)").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(0.06), in: Capsule())
                Spacer()
                Button("Open folder") { NSWorkspace.shared.open(model.destination) }.buttonStyle(.borderless).font(.caption)
            }
            if model.saved.isEmpty {
                HStack(spacing: 13) {
                    Image(systemName: "tray.and.arrow.down").font(.title3).foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A home for your highlights").font(.callout)
                        Text("Downloaded videos and clips will appear here.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("MP4").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
                }.padding(18).background(surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.saved) { video in
                            HStack(spacing: 12) {
                                Button { model.openSaved(video) } label: { Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(accent) }.buttonStyle(.plain).disabled(model.loading).help("Play downloaded video")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(video.title).font(.callout).lineLimit(1)
                                    Text("\(video.detail) · \(video.date.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: video.path)]) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Show in Finder")
                                Menu {
                                    Button("Remove from history", role: .destructive) { model.removeHistory(video) }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
                            }.padding(12).background(surface, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }.frame(minHeight: 80, maxHeight: 155)
            }
        }
    }
}

struct NativePlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        if ProcessInfo.processInfo.arguments.contains("--silent-preview") { player.isMuted = true; player.volume = 0 }
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(enabled ? Color.black : Color.secondary)
            .background(enabled ? accent.opacity(configuration.isPressed ? 0.75 : 1) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
