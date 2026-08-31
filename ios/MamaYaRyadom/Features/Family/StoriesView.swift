import AVFoundation
import SwiftUI

// MARK: - Family Stories

struct StoriesView: View {
    @State private var model = StoriesViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.stories.isEmpty {
                    Text(L10n.storiesEmpty)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(Palette.card, in: .rect(cornerRadius: 20))
                } else {
                    ForEach(model.stories) { story in
                        storyCard(story)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Palette.background)
        .navigationTitle(L10n.storiesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onDisappear { model.stopPlayback() }
    }

    private func storyCard(_ story: FamilyStory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(story.question)
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkSecondary)
                .lineSpacing(2)

            if let answer = story.answerText {
                Text("«\(answer)»")
                    .font(Typography.display(20))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(4)
            }

            if story.hasVoice {
                Button {
                    Task { await model.togglePlayback(story) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.playingId == story.id ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 26))
                        Text(L10n.storiesVoice)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }

            if let date = story.answeredAt {
                Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: L10n.locale)))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkSecondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }
}

// MARK: - View Model

@Observable
@MainActor
final class StoriesViewModel {
    private(set) var stories: [FamilyStory] = []
    private(set) var playingId: UUID?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?

    func load() async {
        stories = (try? await FamilyAPI().stories()) ?? []
    }

    func togglePlayback(_ story: FamilyStory) async {
        if playingId == story.id {
            stopPlayback()
            return
        }
        guard let fileId = story.voiceFileId else { return }
        // The link is signed and short-lived, so it is fetched per play rather
        // than cached: a stale one would fail silently mid-tap.
        guard let url = try? await FamilyAPI().voicePlaybackURL(fileId: fileId) else { return }
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        // Without this the row keeps showing "stop" after the note has played
        // out, and the next tap only clears the stale state instead of
        // replaying. The same observer is what surfaces a failed load, which
        // Ogg/Opus notes currently always are.
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
        playingId = story.id
    }

    func stopPlayback() {
        player?.pause()
        player = nil
        playingId = nil
        for observer in [endObserver, failureObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
        failureObserver = nil
    }
}

#Preview {
    NavigationStack { StoriesView() }
}
