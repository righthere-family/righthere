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

private struct WidgetPalette {
    let dark: Bool

    private func pick(_ light: UInt32, _ night: UInt32) -> Color {
        let hex = dark ? night : light
        return Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var ink: Color { pick(0x33291F, 0xEDE6D8) }
    var inkSecondary: Color { pick(0x7A6F62, 0xA99C8B) }
    var background: Color { pick(0xF5F0E7, 0x1E1913) }
    var backgroundLift: Color { pick(0xFFFCF5, 0x272119) }
    var card: Color { pick(0xFFFFFF, 0x2A241C) }
    var leaf: Color { pick(0x3F7A4E, 0x6FA97E) }
    var honey: Color { pick(0x9A6410, 0xC99B3F) }
    var honeyBright: Color { pick(0xB8791A, 0xD9B268) }
    var cherry: Color { pick(0x8E3A4C, 0xC4818E) }
    var hairline: Color { pick(0xE2D9C7, 0x3A3128) }
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
    @Environment(\.colorScheme) private var scheme
    var entry: MamaEntry

    private var palette: WidgetPalette { WidgetPalette(dark: scheme == .dark) }
    private var compact: Bool { family == .systemSmall }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                empty
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [palette.backgroundLift, palette.background],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Content

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(snapshot)

            Text(statusWord(snapshot.status.state))
                .font(.custom("CormorantGaramond-SemiBold", size: compact ? 26 : 32))
                .foregroundStyle(statusColor(snapshot.status.state))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, compact ? 3 : 4)

            secondLine(snapshot)

            Spacer(minLength: 6)

            if let week = snapshot.week, !week.isEmpty {
                weekStrip(week)
            } else {
                SignalScene(palette: palette, compact: compact)
                    .frame(height: compact ? 26 : 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ snapshot: WidgetSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(who(snapshot).uppercased())
                .font(.system(size: compact ? 9.5 : 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(palette.inkSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            BrandGlyph(palette: palette)
                .frame(width: 22, height: 15)
        }
    }

    @ViewBuilder
    private func secondLine(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 7) {
            if snapshot.status.state == "ok" {
                Text(timeText(snapshot))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.inkSecondary)
                if snapshot.streak >= 2 {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkle").font(.system(size: 8.5))
                        Text("\(snapshot.streak)").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(palette.honey)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(palette.honeyBright.opacity(0.15), in: .capsule)
                }
            } else if let quote = snapshot.status.quote, !quote.isEmpty, !compact {
                Text("«\(quote)»")
                    .font(.custom("CormorantGaramond-SemiBold", size: 15))
                    .foregroundStyle(palette.cherry)
                    .lineLimit(1)
            } else {
                Text(detailLine(snapshot))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 3)
    }

    // MARK: - Week

    private func weekStrip(_ week: [WidgetSnapshot.WeekDay]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                VStack(spacing: compact ? 4 : 5) {
                    Text(weekdayLetter(day.date))
                        .font(.system(size: compact ? 8.5 : 9.5, weight: .medium))
                        .foregroundStyle(palette.inkSecondary.opacity(index == week.count - 1 ? 1 : 0.7))
                    Circle()
                        .fill(markColor(day.mark))
                        .frame(width: compact ? 7 : 8, height: compact ? 7 : 8)
                        .overlay {
                            if day.mark == "pending" {
                                Circle().strokeBorder(palette.honeyBright.opacity(0.7), lineWidth: 1.2)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if index == week.count - 1 {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(palette.honeyBright.opacity(0.13))
                    }
                }
            }
        }
        .padding(.top, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)
                .padding(.horizontal, 2)
                .offset(y: -6)
        }
    }

    private func weekdayLetter(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: iso) else { return "" }
        let out = DateFormatter()
        out.locale = widgetLocale
        out.setLocalizedDateFormatFromTemplate("EEEEE")
        return out.string(from: date).lowercased()
    }

    private func markColor(_ mark: String) -> Color {
        switch mark {
        case "ok": palette.leaf
        case "alert": palette.cherry
        case "pending": palette.honeyBright.opacity(0.001)
        default: palette.inkSecondary.opacity(0.28)
        }
    }

    // MARK: - Empty

    private var empty: some View {
        VStack(alignment: .leading, spacing: 5) {
            BrandGlyph(palette: palette)
                .frame(width: 26, height: 18)
            Text(localized("widget.displayName"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text(localized("widget.openApp"))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Text

    private func who(_ snapshot: WidgetSnapshot) -> String {
        if compact { return snapshot.parent.displayName }
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
        case "ok": palette.leaf
        case "not_ok", "quiet": palette.cherry
        case "reminded": palette.honey
        default: palette.ink
        }
    }

    private func detailLine(_ snapshot: WidgetSnapshot) -> String {
        Date.now.formatted(.dateTime.day().month().locale(widgetLocale))
    }

    private func timeText(_ snapshot: WidgetSnapshot) -> String {
        guard let at = snapshot.status.at else { return "" }
        var style = Date.FormatStyle(date: .omitted, time: .shortened).locale(widgetLocale)
        if let zone = TimeZone(identifier: snapshot.parent.timezone) {
            style.timeZone = zone
        }
        return at.formatted(style)
    }

    private var widgetLocale: Locale {
        let lang = SharedStore.appLanguage
        return lang.isEmpty ? .autoupdatingCurrent : Locale(identifier: lang)
    }
}

// MARK: - Brand Glyph

private struct BrandGlyph: View {
    let palette: WidgetPalette

    var body: some View {
        Canvas { context, size in
            let radius = size.width * 0.42
            let center = CGPoint(x: size.width / 2, y: size.height * 0.96)
            let start = Angle.degrees(202)
            let end = Angle.degrees(-22)

            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            context.stroke(
                arc,
                with: .color(palette.honeyBright.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [0.1, 3.4])
            )

            let sun = CGPoint(x: center.x, y: center.y - radius - size.height * 0.24)
            context.fill(
                Path(ellipseIn: CGRect(x: sun.x - 1.7, y: sun.y - 1.7, width: 3.4, height: 3.4)),
                with: .color(palette.honeyBright)
            )

            let mom = CGPoint(x: center.x + radius * cos(start.radians), y: center.y + radius * sin(start.radians))
            let child = CGPoint(x: center.x + radius * cos(end.radians), y: center.y + radius * sin(end.radians))
            context.fill(
                Path(ellipseIn: CGRect(x: mom.x - 2.6, y: mom.y - 2.6, width: 5.2, height: 5.2)),
                with: .color(palette.honeyBright)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: child.x - 2.2, y: child.y - 2.2, width: 4.4, height: 4.4)),
                with: .color(palette.ink.opacity(0.75))
            )
        }
    }
}

// MARK: - Signal Scene

private struct SignalScene: View {
    let palette: WidgetPalette
    let compact: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let baseY = geo.size.height - 6

            ZStack {
                WidgetArc()
                    .stroke(
                        palette.honeyBright.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 4.6])
                    )
                    .frame(width: width - 12, height: compact ? 20 : 26)
                    .position(x: width / 2, y: baseY - (compact ? 10 : 13))

                Circle()
                    .fill(palette.honeyBright)
                    .frame(width: 8, height: 8)
                    .position(x: 6, y: baseY)

                Circle()
                    .fill(palette.ink)
                    .frame(width: 8, height: 8)
                    .position(x: width - 6, y: baseY)
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
