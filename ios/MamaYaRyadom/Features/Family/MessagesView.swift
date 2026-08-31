import AVFoundation
import SwiftUI

// MARK: - Parent Messages

// Everything the parents wrote, spoke or photographed for the family outside
// the morning button. The bot promises "the family will see this" — this
// screen is where that promise is kept.
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

    private func voiceRow(_ message: ParentMessage) -> some View {
        Button {
            Task { await model.togglePlayback(message) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.playingId == message.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Palette.accent)
                Text(L10n.messagesVoice)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
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

// MARK: - View Model

@Observable
@MainActor
final class MessagesViewModel {
    private(set) var messages: [ParentMessage] = []
    private(set) var photoURLs: [UUID: URL] = [:]
    private(set) var isLoading = true
    private(set) var playingId: UUID?
    private var parentNames: [UUID: String] = [:]
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?

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
        // Photo links are signed and short-lived, fetched together so cards
        // fill in one pass instead of popping one by one.
        await withTaskGroup(of: (UUID, URL)?.self) { group in
            for message in loaded {
                guard let fileId = message.photoFileId else { continue }
                group.addTask {
                    guard let url = try? await FamilyAPI().voicePlaybackURL(fileId: fileId) else {
                        return nil
                    }
                    return (message.id, url)
                }
            }
            for await pair in group {
                if let (id, url) = pair { photoURLs[id] = url }
            }
        }
    }

    func parentName(for id: UUID) -> String {
        parentNames[id] ?? L10n.familyParentKindMom
    }

    func togglePlayback(_ message: ParentMessage) async {
        if playingId == message.id {
            stopPlayback()
            return
        }
        guard let fileId = message.voiceFileId else { return }
        guard let url = try? await FamilyAPI().voicePlaybackURL(fileId: fileId) else { return }
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopPlayback() }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopPlayback() }
        }
        player?.play()
        playingId = message.id
    }

    func stopPlayback() {
        player?.pause()
        player = nil
        playingId = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
    }
}

#Preview {
    NavigationStack { MessagesView() }
}
