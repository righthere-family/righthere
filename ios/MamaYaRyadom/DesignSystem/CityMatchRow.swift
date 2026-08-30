import SwiftUI

// MARK: - City Match Row

struct CityMatchRow: View {
    let match: CitySearch.Match

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(match.title)
                .font(.system(size: 15))
                .foregroundStyle(Palette.ink)
            if !match.subtitle.isEmpty {
                Text(match.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
