import Foundation

struct TodayCardState: Identifiable {
    let id: UUID

    
    struct WeekDay: Identifiable {
        let id: Date
        let title: String
        let isToday: Bool
        let result: WeekDayResult
    }
    
    struct MedicationsInfo {
        let taken: Int
        let total: Int
    }
    
    let name: String
    let city: String
    let timezone: String
    let status: DayStatus
    let streak: Int
    
    let weekdays: [WeekDay]
    let medicationsInfo: MedicationsInfo
    let eveningIsOk: Bool?
    var isWaiting = false
    var inviteCode: String?
}

// MARK: - Skeleton Sample

extension TodayCardState {
    static let skeleton = TodayCardState(
        id: UUID(),
        name: String(repeating: "\u{2007}", count: 6),
        city: String(repeating: "\u{2007}", count: 8),
        timezone: "Europe/Moscow",
        status: .stillMorning(usualBy: nil),
        streak: 0,
        weekdays: (0..<7).map { offset in
            WeekDay(
                id: Date(timeIntervalSinceReferenceDate: Double(offset) * 86_400),
                title: "··",
                isToday: false,
                result: .blank
            )
        },
        medicationsInfo: MedicationsInfo(taken: 0, total: 1),
        eveningIsOk: nil
    )
}
