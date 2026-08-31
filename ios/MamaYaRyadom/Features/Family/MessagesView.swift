import AVFoundation
import SwiftUI

// MARK: - Parent Messages

struct MessagesView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var model = MessagesViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.isLoading {
                    skeleton
                } else if model.messages.isEmpty {
                    Text(L10n.messagesEmpty)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(Palette.card, in: .rect(cornerRadius: 20))
                } else {
                    ForEach(model.messages) { message in
                        messageCard(message)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Palette.background)
        .navigationTitle(L10n.messagesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(using: dependencies.checkinService) }
        .onDisappear { model.stopPlayback() }
    }

    // MARK: - Card

    private func messageCard(_ message: ParentMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.parentName(for: message.parentId))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Text(message.createdAt.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened, locale: L10n.locale)
                ))
                .font(.system(size: 11))
                .foregroundStyle(Palette.inkSecondary.opacity(0.7))
            }

            if let body = message.body, !body.isEmpty {
                Text("«\(body)»")
                    .font(Typography.display(20))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(3)
            }

            if message.voiceFileId != nil {
                voiceRow(message)
            }

            if message.photoFileId != nil {
                photoView(message)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: .rect(cornerRadius: 18))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }

    // MARK: - Voice

    private func voiceRow(_ message: ParentMessage) -> some View {
        Button {
            Task { await model.togglePlayback(message) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.playingId == message.id ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Palette.accent)
                if let track = model.tracks[message.id] {
                    WaveformBars(
                        samples: track.samples,
                        progress: model.playingId == message.id ? model.progress : 0
                    )
                    .frame(height: 26)
                    Text(model.timeLabel(for: message))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    Text(L10n.messagesVoice)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkSecondary)
                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func photoView(_ message: ParentMessage) -> some View {
        if let url = model.photoURLs[message.id] {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Rectangle().fill(Palette.background)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    private var skeleton: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(repeating: "\u{2007}", count: 12))
                        .font(.system(size: 13, weight: .semibold))
                    Text(String(repeating: "\u{2007}", count: 30))
                        .font(Typography.quote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .background(Palette.card, in: .rect(cornerRadius: 20))
            }
        }
        .skeleton()
    }
}

// MARK: - Waveform

private struct WaveformBars: View {
    let samples: [Float]
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let count = max(samples.count, 1)
            let step = geo.size.width / CGFloat(count)
            let barWidth = max(2, step * 0.62)
            let played = Int((progress * Double(count)).rounded())
            HStack(alignment: .center, spacing: step - barWidth) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(index < played ? Palette.accent : Palette.inkSecondary.opacity(0.35))
                        .frame(
                            width: barWidth,
                            height: max(4, geo.size.height * CGFloat(samples[index]))
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}

// MARK: - View Model

@Observable
@MainActor
final class MessagesViewModel {
    struct VoiceTrack {
        let data: Data
        let duration: TimeInterval
        let samples: [Float]
    }

    private(set) var messages: [ParentMessage] = []
    private(set) var photoURLs: [UUID: URL] = [:]
    private(set) var tracks: [UUID: VoiceTrack] = [:]
    private(set) var isLoading = true
    private(set) var playingId: UUID?
    private(set) var progress: Double = 0
    private var parentNames: [UUID: String] = [:]
    private var player: AVAudioPlayer?
    private var ticker: Timer?

    func load(using service: any CheckinService) async {
        async let feed = (try? FamilyAPI().parentMessages()) ?? []
        async let snapshot = try? service.todaySnapshot()
        let (loaded, snap) = await (feed, snapshot)
        if let snap {
            for member in [snap.parent] + snap.others.map(\.parent) {
                parentNames[member.id] = member.displayName
            }
        }
        messages = loaded
        isLoading = false

        // Photos resolve to short-lived signed links; voice notes are small,
        // so they download whole — the waveform and duration need the bytes,
        // and AVPlayer streaming needs range support the worker does not have.
        await withTaskGroup(of: Payload?.self) { group in
            for message in loaded {
                if let fileId = message.photoFileId {
                    group.addTask {
                        guard let url = try? await FamilyAPI().voicePlaybackURL(fileId: fileId) else {
                            return nil
                        }
                        return .photo(message.id, url)
                    }
                }
                if let fileId = message.voiceFileId {
                    group.addTask {
                        guard let track = await Self.downloadTrack(fileId: fileId) else { return nil }
                        return .voice(message.id, track)
                    }
                }
            }
            for await payload in group {
                switch payload {
                case .photo(let id, let url): photoURLs[id] = url
                case .voice(let id, let track): tracks[id] = track
                case nil: break
                }
            }
        }
    }

    private enum Payload {
        case photo(UUID, URL)
        case voice(UUID, VoiceTrack)
    }

    func parentName(for id: UUID) -> String {
        parentNames[id] ?? L10n.familyParentKindMom
    }

    func timeLabel(for message: ParentMessage) -> String {
        guard let track = tracks[message.id] else { return "" }
        let seconds = playingId == message.id
            ? track.duration * (1 - progress)
            : track.duration
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Playback

    func togglePlayback(_ message: ParentMessage) async {
        if playingId == message.id {
            stopPlayback()
            return
        }
        stopPlayback()
        var track = tracks[message.id]
        if track == nil, let fileId = message.voiceFileId {
            track = await Self.downloadTrack(fileId: fileId)
            if let track { tracks[message.id] = track }
        }
        guard let track else { return }

        // Route to the speakers even with the silent switch on: a voice note
        // is something the user explicitly asked to hear.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let audio = try? AVAudioPlayer(data: track.data, fileTypeHint: AVFileType.caf.rawValue) else {
            return
        }
        player = audio
        audio.play()
        playingId = message.id
        progress = 0
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let player else { return }
        if player.isPlaying {
            progress = player.duration > 0 ? player.currentTime / player.duration : 0
        } else {
            stopPlayback()
        }
    }

    func stopPlayback() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
        playingId = nil
        progress = 0
    }

    // MARK: - Voice Download

    private nonisolated static func downloadTrack(fileId: String) async -> VoiceTrack? {
        guard let url = try? await FamilyAPI().voicePlaybackURL(fileId: fileId),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty
        else { return nil }
        let analyzed = analyze(data)
        return VoiceTrack(
            data: data,
            duration: analyzed?.duration ?? 0,
            samples: analyzed?.samples ?? Array(repeating: 0.35, count: 36)
        )
    }

    private nonisolated static func analyze(_ data: Data) -> (duration: TimeInterval, samples: [Float])? {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: temp) }
        guard (try? data.write(to: temp)) != nil,
              let file = try? AVAudioFile(forReading: temp)
        else { return nil }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?.pointee
        else { return nil }
        let length = Int(buffer.frameLength)
        guard length > 0 else { return nil }
        let duration = Double(length) / format.sampleRate

        let buckets = 36
        let per = max(1, length / buckets)
        var samples = [Float](repeating: 0, count: buckets)
        for bucket in 0..<buckets {
            let start = bucket * per
            let end = min(length, start + per)
            guard start < end else { break }
            var sum: Float = 0
            for i in start..<end { sum += abs(channel[i]) }
            samples[bucket] = sum / Float(end - start)
        }
        let peak = max(samples.max() ?? 0, 0.0001)
        return (duration, samples.map { max(0.12, min(1, $0 / peak)) })
    }
}

#Preview {
    NavigationStack { MessagesView() }
}
