import SwiftUI

struct StreakBadge: View {
    let count: Int
    
    private var isMilestone: Bool {
        [7, 30, 100, 365].contains(count)
    }
    
    var body: some View {
        if count > 1 {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11))
                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isMilestone ? .white : Palette.accent)
            
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isMilestone ? Palette.accentBright : Palette.accentBright.opacity(0.14), in: .capsule)
        }
    }
    
}

#Preview {
    VStack(spacing: 12) {
        StreakBadge(count: 3)
        StreakBadge(count: 12)
        StreakBadge(count: 30)
        StreakBadge(count: 100)
    }
    .background(Palette.background)
    
}

#Preview("Dark") {
    VStack(spacing: 12) {
        StreakBadge(count: 3)
        StreakBadge(count: 12)
        StreakBadge(count: 30)
        StreakBadge(count: 100)
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
