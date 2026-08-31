import SwiftUI

// MARK: - Root Toolbar

// The three root tabs share one header: a quiet title on the leading side and
// the brand mark trailing. The navigation bar itself always exists (with a
// hidden background) so pushes never toggle bar visibility — toggling is what
// made outgoing screens jump. On iOS 26 the liquid-glass capsules are removed:
// glass reads as "tappable", and neither element is.
private struct RootToolbar: ViewModifier {
    let title: String
    var settingsAction: (() -> Void)?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .topBarLeading) { leading }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) { mark }
                    .sharedBackgroundVisibility(.hidden)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            content.toolbar {
                ToolbarItem(placement: .topBarLeading) { leading }
                ToolbarItem(placement: .topBarTrailing) { mark }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var leading: some View {
        HStack(spacing: 10) {
            titleText
            if let settingsAction {
                Button(action: settingsAction) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Palette.inkSecondary)
            .fixedSize()
    }

    private var mark: some View {
        BrandMark()
            .frame(width: 30, height: 27)
    }
}

extension View {
    func rootToolbar(title: String, settingsAction: (() -> Void)? = nil) -> some View {
        modifier(RootToolbar(title: title, settingsAction: settingsAction))
    }
}
