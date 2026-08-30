import SwiftUI
import UIKit

// MARK: - Doctor Report

// One A4 page: who, which period, medications, and every day of the month.
// Rendered locally — health data never leaves the phone for this.
struct DoctorReportView: View {
    let parent: Parent
    let monthTitle: String
    let records: [DayRecord]
    let meds: [MedInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.exportTitle)
                .font(.system(size: 20, weight: .semibold))
            Text("\(parent.displayName) · \(parent.cityName)")
                .font(.system(size: 14))
            Text(L10n.exportPeriod(monthTitle))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if !meds.isEmpty {
                Text(L10n.exportMeds)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.top, 6)
                ForEach(meds) { med in
                    Text("• \(med.title) — \(med.times.joined(separator: ", "))")
                        .font(.system(size: 13))
                }
            }

            Text(L10n.exportDays)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 6)

            let columns = [GridItem(.adaptive(minimum: 120), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(records) { record in
                    Text("\(record.day): \(mark(record.mark))")
                        .font(.system(size: 11, design: .monospaced))
                }
            }
            Spacer()
        }
        .padding(36)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(.white)
        .foregroundStyle(.black)
    }

    private func mark(_ mark: DayMark) -> String {
        switch mark {
        case .allGood(let time): "OK \(time)"
        case .notOk: "не очень"
        case .missed: "пропуск"
        case .paused: "пауза"
        case .upcoming: "—"
        }
    }
}

// MARK: - PDF

@MainActor
enum DoctorReportPDF {
    static func render(
        parent: Parent,
        monthTitle: String,
        records: [DayRecord],
        meds: [MedInfo]
    ) -> URL? {
        let view = DoctorReportView(
            parent: parent,
            monthTitle: monthTitle,
            records: records,
            meds: meds
        )
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 595, height: 842)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("report-\(parent.displayName)-\(monthTitle).pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        return url
    }
}

// MARK: - Share

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
