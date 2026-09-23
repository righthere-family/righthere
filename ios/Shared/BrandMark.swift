import SwiftUI

// MARK: - Brand Mark

struct BrandMark: View {
    // The mark lives in the navigation bar of both themes. Its colours were
    // pinned to the light palette, so at night the arc and the child's dot
    // sank into the background and only the sun was left.
    @Environment(\.colorScheme) private var scheme

    private var ink: Color { scheme == .dark ? hex(0xE8E6E1) : hex(0x33291F) }
    private var honey: Color { scheme == .dark ? hex(0xD9B268) : hex(0xB8791A) }
    private var arcOpacity: Double { scheme == .dark ? 0.55 : 0.4 }

    private func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var body: some View {
        Canvas { context, size in
            let radius = size.width * 0.40
            let center = CGPoint(x: size.width / 2, y: size.height * 0.95)
            let start = Angle.degrees(205)
            let end = Angle.degrees(-25)

            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            context.stroke(
                arc,
                with: .color(ink.opacity(arcOpacity)),
                style: StrokeStyle(lineWidth: 2.1, lineCap: .round, dash: [0.1, 4.8])
            )

            let sun = CGPoint(x: size.width / 2, y: center.y - radius - size.height * 0.28)
            context.fill(
                Path(ellipseIn: CGRect(x: sun.x - 2.1, y: sun.y - 2.1, width: 4.2, height: 4.2)),
                with: .color(honey)
            )
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4
                let inner = CGPoint(x: sun.x + 3.4 * cos(angle), y: sun.y + 3.4 * sin(angle))
                let outer = CGPoint(x: sun.x + 4.9 * cos(angle), y: sun.y + 4.9 * sin(angle))
                var ray = Path()
                ray.move(to: inner)
                ray.addLine(to: outer)
                context.stroke(ray, with: .color(honey), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }

            let momPoint = CGPoint(
                x: center.x + radius * cos(start.radians),
                y: center.y + radius * sin(start.radians)
            )
            let childPoint = CGPoint(
                x: center.x + radius * cos(end.radians),
                y: center.y + radius * sin(end.radians)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: momPoint.x - 3.4, y: momPoint.y - 3.4, width: 6.8, height: 6.8)),
                with: .color(honey)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: childPoint.x - 3.4, y: childPoint.y - 3.4, width: 6.8, height: 6.8)),
                with: .color(ink)
            )
        }
    }
}
