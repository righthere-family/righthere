import SwiftUI

// MARK: - Paywall Sheet

// Gates present the paywall as a sheet at the exact moment someone runs into
// a limit: the paywall answers a question they just asked, it never ambushes.
struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaywallView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.premiumDone) { dismiss() }
                            .foregroundStyle(Palette.accent)
                    }
                }
        }
    }
}

// MARK: - Premium Hint Card

// Shown in place of the action that crossed the free limit. Warm, one line of
// why, one honey link — never a wall.
struct PremiumHintCard: View {
    let title: String
    let hint: String
    let onLearnMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.accentBright)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
            Text(hint)
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkSecondary)
                .lineSpacing(3)
                .padding(.top, 6)
            Button(action: onLearnMore) {
                Text(L10n.premiumLearnMore)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }
}

#Preview {
    VStack(spacing: 14) {
        PremiumHintCard(
            title: L10n.premiumMeds,
            hint: L10n.premiumMedsHint,
            onLearnMore: {}
        )
    }
    .padding(20)
    .frame(maxHeight: .infinity)
    .background(Palette.background)
}
