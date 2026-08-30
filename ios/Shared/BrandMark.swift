import SwiftUI

// MARK: - Brand Mark

struct BrandMark: View {
    private let ink = Color(red: 0x33 / 255, green: 0x29 / 255, blue: 0x1F / 255)
    private let honey = Color(red: 0xB8 / 255, green: 0x79 / 255, blue: 0x1A / 255)

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
                with: .color(ink.opacity(0.35)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )

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
