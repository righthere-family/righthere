import SwiftUI

// MARK: - Underline Field

// The form language of the app: an entry is a line in a warm document, not a
// box in a questionnaire. The written value is serif italic; the underline is
// quiet until the field is focused, then turns honey.
struct FormUnderlineField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .keyboardType(keyboard)
                .font(Typography.display(22))
                .foregroundStyle(Palette.ink)
                .focused($isFocused)
                .padding(.bottom, 8)
            Rectangle()
                .fill(isFocused ? Palette.accentBright : Palette.accentBright.opacity(0.22))
                .frame(height: 1.5)
                .animation(.easeOut(duration: 0.2), value: isFocused)
        }
    }
}

// MARK: - Underline Value Row

// Same visual language for values picked from a menu rather than typed.
struct FormUnderlineValue<Menu: View>: View {
    let label: String
    let value: String
    var monospaced = false
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkSecondary)
            SwiftUI.Menu {
                menu()
            } label: {
                HStack(spacing: 7) {
                    Text(value)
                        .font(monospaced ? .system(size: 19, design: .monospaced) : Typography.display(22))
                        .foregroundStyle(Palette.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Spacer()
                }
                .padding(.bottom, 8)
                .contentShape(.rect)
            }
            Rectangle()
                .fill(Palette.accentBright.opacity(0.22))
                .frame(height: 1.5)
        }
    }
}

// MARK: - Primary Button

// Disabled is honest: muted beige, not sickly translucent honey. Honey means
// "you can press this" and must never lie.
struct FormPrimaryButton: View {
    let title: String
    var isEnabled = true
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isEnabled ? .white : Palette.inkSecondary.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                isEnabled ? Palette.accent : Palette.formDisabled,
                in: .rect(cornerRadius: 16)
            )
        }
        .disabled(!isEnabled || isBusy)
        .animation(.easeOut(duration: 0.2), value: isEnabled)
    }
}

#Preview {
    struct Host: View {
        @State private var name = ""
        @State private var city = "Саратов"

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                FormUnderlineField(label: "Как его зовут", placeholder: "Папа", text: $name)
                FormUnderlineField(label: "Его город", placeholder: "Начни вводить город", text: $city)
                FormUnderlineValue(label: "Утреннее сообщение", value: "09:00", monospaced: true) {
                    Button("09:00") {}
                }
                FormPrimaryButton(title: "Создать приглашение", isEnabled: false) {}
                FormPrimaryButton(title: "Создать приглашение") {}
            }
            .padding(24)
            .background(Palette.card, in: .rect(cornerRadius: 22))
            .padding(20)
            .frame(maxHeight: .infinity)
            .background(Palette.background)
        }
    }
    return Host()
}
