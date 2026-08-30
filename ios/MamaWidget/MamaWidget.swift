import WidgetKit
import SwiftUI

// MARK: - Widget Locale

// The widget renders in its own process; the app's language choice arrives
// through the shared app group. Empty means "follow the system".
private var widgetBundle: Bundle {
    let lang = SharedStore.appLanguage
    guard !lang.isEmpty,
          let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
        return .main
    }
    return bundle
}

private func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: widgetBundle)
}

// MARK: - Palette

private enum WidgetPalette {
    static let ink = dynamic(light: 0x33291F, dark: 0xEDE6D8)
    static let inkSecondary = dynamic(light: 0x7A6F62, dark: 0xA99C8B)
    static let background = dynamic(light: 0xF5F0E7, dark: 0x1E1913)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2A241C)
    static let leaf = dynamic(light: 0x3F7A4E, dark: 0x6FA97E)
    static let honey = dynamic(light: 0x9A6410, dark: 0xC99B3F)
    static let honeyBright = dynamic(light: 0xB8791A, dark: 0xD9B268)
    static let cherry = dynamic(light: 0x8E3A4C, dark: 0xC4818E)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Entry

struct MamaEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - Sendable Box

private struct SendableBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in _: Context) -> MamaEntry {
        MamaEntry(date: .now, snapshot: cached())
    }

    func getSnapshot(in _: Context, completion: @escaping (MamaEntry) -> Void) {
        completion(MamaEntry(date: .now, snapshot: cached()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<MamaEntry>) -> Void) {
        let box = SendableBox(completion)
        Task {
            let snapshot = await fetch() ?? cached()
            let entry = MamaEntry(date: .now, snapshot: snapshot)
            let refresh = Date.now.addingTimeInterval(20 * 60)
            box.value(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private func cached() -> WidgetSnapshot? {
        SharedStore.cachedSnapshot.flatMap(WidgetSnapshot.decode)
    }

    private func fetch() async -> WidgetSnapshot? {
        let base = SharedStore.supabaseURL
        let key = SharedStore.supabaseAnonKey
        let token = SharedStore.familyToken
        guard !base.isEmpty, !key.isEmpty, !token.isEmpty,
              let url = URL(string: "\(base)/rest/v1/rpc/app_snapshot") else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(["p_app_token": token])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let snapshot = WidgetSnapshot.decode(data) else { return nil }
        SharedStore.cachedSnapshot = data
        return snapshot
    }
}

// MARK: - View

struct MamaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: MamaEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                empty
            }
        }
        .containerBackground(for: .widget) { WidgetPalette.background }
    }

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        ZStack(alignment: .topLeading) {
            SignalScene(
                timeCapsule: snapshot.status.state == "ok" ? timeText(snapshot) : nil,
                compact: family == .systemSmall
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(who(snapshot).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(WidgetPalette.inkSecondary)
                Text(statusWord(snapshot.status.state))
                    .font(.custom("CormorantGaramond-SemiBold", size: family == .systemSmall ? 21 : 27))
                    .foregroundStyle(statusColor(snapshot.status.state))
                    .minimumScaleFactor(0.6)
                    .lineLimit(family == .systemSmall ? 2 : 1)
                if family != .systemSmall, let quote = snapshot.status.quote, !quote.isEmpty {
                    Text("«\(quote)»")
                        .font(.custom("CormorantGaramond-SemiBoldItalic", size: 15))
                        .foregroundStyle(WidgetPalette.cherry)
                        .lineLimit(1)
                } else if family != .systemSmall, snapshot.status.state == "ok", snapshot.streak >= 2 {
                    Text(String(format: localized("status.streak"), snapshot.streak))
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetPalette.inkSecondary)
                } else if snapshot.status.state != "ok" {
                    Text(detailLine(snapshot))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(WidgetPalette.inkSecondary)
                }
                if family == .systemSmall, snapshot.status.state == "ok" {
                    Text(timeText(snapshot))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(WidgetPalette.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("widget.displayName"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WidgetPalette.ink)
            Text(localized("widget.openApp"))
                .font(.system(size: 10))
                .foregroundStyle(WidgetPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func who(_ snapshot: WidgetSnapshot) -> String {
        if family == .systemSmall {
            return snapshot.parent.displayName
        }
        let city = snapshot.parent.city.map { " · \($0)" } ?? ""
        return snapshot.parent.displayName + city
    }

    private func statusWord(_ state: String) -> String {
        switch state {
        case "ok": localized("status.allGood")
        case "not_ok": localized("widget.notOk")
        case "quiet": localized("status.quiet")
        case "reminded": localized("status.reminded")
        case "paused": localized("status.paused")
        case "waiting_parent": localized("waiting.title")
        default: localized("status.stillMorning")
        }
    }

    private func statusColor(_ state: String) -> Color {
        switch state {
        case "ok": WidgetPalette.leaf
        case "not_ok": WidgetPalette.cherry
        case "reminded": WidgetPalette.honey
        default: WidgetPalette.ink
        }
    }

    private func detailLine(_ snapshot: WidgetSnapshot) -> String {
        Date.now.formatted(.dateTime.day().month())
    }

    private func timeText(_ snapshot: WidgetSnapshot) -> String {
        guard let at = snapshot.status.at else { return "" }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        if let zone = TimeZone(identifier: snapshot.parent.timezone) {
            style.timeZone = zone
        }
        return at.formatted(style)
    }
}

// MARK: - Signal Scene

private struct SignalScene: View {
    let timeCapsule: String?
    let compact: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let baseY = geo.size.height - 8
            let momX: CGFloat = 6
            let childX = width - 6

            ZStack {
                WidgetArc()
                    .stroke(
                        WidgetPalette.honeyBright.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 4.6])
                    )
                    .frame(width: width - 12, height: compact ? 26 : 34)
                    .position(x: width / 2, y: baseY - (compact ? 13 : 17))

                Circle()
                    .fill(WidgetPalette.honeyBright)
                    .frame(width: 8, height: 8)
                    .position(x: momX, y: baseY)

                Circle()
                    .fill(WidgetPalette.ink)
                    .frame(width: 8, height: 8)
                    .position(x: childX, y: baseY)

                if let time = timeCapsule, !time.isEmpty, !compact {
                    Text(time)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(WidgetPalette.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(WidgetPalette.card, in: .capsule)
                        .shadow(color: WidgetPalette.ink.opacity(0.12), radius: 4, y: 2)
                        .position(x: childX - 26, y: baseY - 22)
                }
            }
        }
    }
}

private struct WidgetArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.2)
        )
        return path
    }
}

// MARK: - Widget

@main
struct MamaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MamaWidget", provider: Provider()) { entry in
            MamaWidgetView(entry: entry)
        }
        .configurationDisplayName(localized("widget.displayName"))
        .description(localized("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
