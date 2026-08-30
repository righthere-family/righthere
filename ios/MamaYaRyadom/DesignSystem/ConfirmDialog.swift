import SwiftUI

// MARK: - Confirm Dialog

// The house replacement for system confirmation dialogs: a warm card over a
// dimmed background instead of the iOS action sheet. Destructive-only by
// design — the only thing we ever confirm is a deletion.
struct ConfirmDialog: ViewModifier {
    let title: String
    let message: String?
    let actionTitle: String
    @Binding var isPresented: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    dialog
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isPresented)
    }

    // The card slides up from the bottom edge, sheet-like; the dimming fades.
    private var dialog: some View {
        ZStack(alignment: .bottom) {
            Palette.ink.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }
                .transition(.opacity)

            card
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                if let message {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                Button {
                    isPresented = false
                    action()
                } label: {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Palette.alert, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.top, 22)

                Button(L10n.postcardCancel) { isPresented = false }
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 14)
            }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(Palette.card, in: .rect(cornerRadius: 26))
        .shadow(color: Palette.ink.opacity(0.16), radius: 26, y: -6)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

extension View {
    func confirmDialog(
        _ title: String,
        message: String? = nil,
        actionTitle: String,
        isPresented: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        modifier(ConfirmDialog(
            title: title,
            message: message,
            actionTitle: actionTitle,
            isPresented: isPresented,
            action: action
        ))
    }
}

#Preview {
    Palette.background
        .ignoresSafeArea()
        .confirmDialog(
            "Удалить «День рождения мамы»?",
            message: "Напоминание за неделю больше не придёт.",
            actionTitle: "Удалить",
            isPresented: .constant(true)
        ) {}
}
