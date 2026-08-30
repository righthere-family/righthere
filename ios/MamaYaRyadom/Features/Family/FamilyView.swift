import SwiftUI

// MARK: - Family

struct FamilyView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(AppRouter.self) private var router
    @State private var model = FamilyViewModel()
    @State private var isShowingPaywall = false
    private let purchases = PurchaseModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.members.isEmpty {
                    skeletonCard
                } else {
                    ForEach(model.members) { member in
                        parentCard(member)
                    }
                }
                addParentRow
                messagesRow
                storiesRow
                datesRow
                inviteCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Palette.background)
        .rootToolbar(title: L10n.tabFamily, settingsAction: { router.push(.settings) })
        .task {
            await model.load(using: dependencies.checkinService)
            await purchases.load()
        }
        .sheet(isPresented: $isShowingPaywall) { PaywallSheet() }
    }

    // MARK: - Header

    // MARK: - Mom

    private func parentCard(_ member: FamilyViewModel.Member) -> some View {
        Button {
            router.push(.parentProfile(member.id))
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(member.isConnected ? Palette.accentBright : Palette.inkSecondary.opacity(0.35))
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.line)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(member.statusLine)
                        .font(.system(size: 13))
                        .foregroundStyle(member.isConnected ? Palette.okStrong : Palette.inkSecondary)
                }
                Spacer()
                Text(L10n.medsEdit)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Palette.card, in: .rect(cornerRadius: 20))
            .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Skeleton

    private var skeletonCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Palette.inkSecondary.opacity(0.35))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(repeating: "\u{2007}", count: 16))
                    .font(.system(size: 16, weight: .semibold))
                Text(String(repeating: "\u{2007}", count: 10))
                    .font(.system(size: 13))
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
        .skeleton()
    }

    // MARK: - Add Parent

    private var addParentRow: some View {
        Button {
            // The second parent is where free ends; the first is always open.
            if model.members.count >= 1 && !purchases.hasSubscription {
                isShowingPaywall = true
            } else {
                router.push(.addParent)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.accent)
                Text(L10n.familyAddParent)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.accent)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(Palette.card, in: .rect(cornerRadius: 20))
            .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Messages, Stories & Dates

    private var messagesRow: some View {
        Button {
            router.push(.messages)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.accentBright)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.messagesTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(L10n.messagesRowHint)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Palette.card, in: .rect(cornerRadius: 20))
            .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var storiesRow: some View {
        Button {
            if purchases.hasSubscription {
                router.push(.stories)
            } else {
                isShowingPaywall = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.accentBright)
                VStack(alignment: .leading, spacing: 2) {
                    Text(storiesTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(L10n.storiesRowHint)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                Image(systemName: purchases.hasSubscription ? "chevron.right" : "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Palette.card, in: .rect(cornerRadius: 20))
            .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    // The archive grows for everyone; the teaser tells locked-out families
    // exactly what is waiting behind the door.
    private var storiesTitle: String {
        if purchases.hasSubscription || model.storyCount == 0 {
            return L10n.storiesTitle
        }
        return L10n.storiesPremium(model.storyCount)
    }

    private var datesRow: some View {
        Button {
            router.push(.dates)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.accentBright)
                Text(L10n.datesTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Palette.card, in: .rect(cornerRadius: 20))
            .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Invite Sibling

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.familyInviteTitle)
                .font(Typography.display(22))
                .foregroundStyle(Palette.ink)
            Text(L10n.familyInviteText)
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkSecondary)
                .lineSpacing(3)
                .padding(.top, 8)

            if let url = model.joinURL {
                ShareLink(item: L10n.familyInviteMessage(url.absoluteString)) {
                    Label(L10n.familyInviteButton, systemImage: "person.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Palette.accent, in: .rect(cornerRadius: 14))
                }
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }

    // MARK: - Subscription

}

// MARK: - View Model

@Observable
@MainActor
final class FamilyViewModel {
    struct Member: Identifiable {
        let id: UUID
        let line: String
        let statusLine: String
        let isConnected: Bool
    }

    private(set) var parent: Parent = .sample
    private(set) var members: [Member] = []
    private(set) var storyCount = 0

    var joinURL: URL? {
        guard AppConfig.hasFamily else { return nil }
        return URL(string: "\(AppConfig.joinBaseURL)/join/\(AppConfig.familyToken)")
    }

    func load(using service: any CheckinService) async {
        guard let snapshot = try? await service.todaySnapshot() else { return }
        parent = snapshot.parent
        storyCount = (try? await FamilyAPI().stories().count) ?? 0
        members = snapshot.everyone.map { member in
            Member(
                id: member.parent.id,
                line: "\(member.parent.displayName) · \(member.parent.cityName)",
                statusLine: member.isWaitingParent ? L10n.familyMomWaiting : L10n.familyMomConnected,
                isConnected: !member.isWaitingParent
            )
        }
    }
}

#Preview {
    NavigationStack { FamilyView() }
        .environment(AppRouter())
}
