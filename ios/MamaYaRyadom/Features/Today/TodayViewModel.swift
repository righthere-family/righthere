import Foundation
import Observation
import WidgetKit

// MARK: - Stage

enum TodayStage: Equatable {
    case loading
    case failed
    case setup
    case waiting(inviteCode: String?)
    case ready
}

// MARK: - View Model

@Observable
@MainActor
final class TodayViewModel {
    private(set) var stage: TodayStage = .loading
    private(set) var parent: Parent = .sample
    private(set) var status: DayStatus = .stillMorning(usualBy: nil)
    private(set) var week: [WeekDayResult] = []
    private(set) var streak = 0
    private(set) var medicationsTaken = 0
    private(set) var medicationsTotal = 0
    private(set) var evening: TodaySnapshot.Evening?
    private(set) var upcomingDate: TodaySnapshot.UpcomingDate?
    private(set) var others: [TodaySnapshot] = []
    private(set) var weeks: [UUID: [WeekDayResult]] = [:]
    private(set) var liveEpoch = 0
    private(set) var isCreatingFamily = false
    private(set) var setupError = false

    var childName = ""
    var childGender = "son"
    var momName = ""
    var cityQuery = ""
    var selectedCity: City?
    var checkinTime = "09:00"
    // The language the bot will speak to mom; defaults to the app's own.
    var botLang = L10n.effectiveLanguage

    let citySearch = CitySearch()

    var citySuggestions: [CitySearch.Match] {
        guard selectedCity == nil else { return [] }
        return citySearch.matches
    }
    
    private static let calendar = Calendar(identifier: .gregorian)
    
    var cardState: TodayCardState {
        cardState(
            for: parent,
            status: status,
            streak: streak,
            medsTaken: medicationsTaken,
            medsTotal: medicationsTotal,
            evening: evening
        )
    }

    var cards: [TodayCardState] {
        [cardState] + others.map {
            cardState(
                for: $0.parent,
                status: $0.status,
                streak: $0.streak,
                medsTaken: $0.medsTaken,
                medsTotal: $0.medsTotal,
                evening: $0.evening
            )
        }
    }

    var parents: [Parent] {
        [parent] + others.map(\.parent)
    }

    private func cardState(
        for parent: Parent,
        status: DayStatus,
        streak: Int,
        medsTaken: Int,
        medsTotal: Int,
        evening: TodaySnapshot.Evening?
    ) -> TodayCardState {
        // Days are counted in the parent's own timezone: the strip shows her
        // days, and the results underneath were computed there too. The locale
        // is applied here, not cached: the in-app language can change.
        var calendar = TodayViewModel.calendar
        calendar.timeZone = TimeZone(identifier: parent.timezone) ?? calendar.timeZone
        calendar.locale = L10n.locale
        let today = calendar.startOfDay(for: .now)
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let results = weeks[parent.id] ?? []
        let weekdays = zip(0..<7, results).compactMap { offset, result -> TodayCardState.WeekDay? in
            guard let date = calendar.date(byAdding: .day, value: offset - 6, to: today) else {
                return nil
            }
            return TodayCardState.WeekDay(
                id: date,
                title: symbols[calendar.component(.weekday, from: date) - 1].lowercased(),
                isToday: offset == 6,
                result: result
            )
        }

        let medicationsInfo = TodayCardState.MedicationsInfo(taken: medsTaken, total: medsTotal)

        return TodayCardState(id: parent.id,
                              name: parent.displayName,
                              city: parent.cityName,
                              timezone: parent.timezone,
                              status: status,
                              streak: streak,
                              weekdays: weekdays,
                              medicationsInfo: medicationsInfo,
                              eveningIsOk: evening?.isOk)
    }

    func choose(_ match: CitySearch.Match) {
        Task {
            selectedCity = await citySearch.resolve(match)
            cityQuery = match.title
            citySearch.clear()
        }
    }

    func cityQueryEdited() {
        citySearch.update(query: cityQuery)
        if let selected = selectedCity, cityQuery != selected.displayName {
            selectedCity = nil
        }
    }

    static let timeOptions = ["07:00", "08:00", "09:00", "10:00", "11:00"]

    // MARK: Loading

    private var socketToken = ""

    func load(using service: any CheckinService) async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "forceWaiting") {
            stage = .waiting(inviteCode: "demo123456")
            return
        }
        #endif
        if !AppConfig.hasFamily,
           let restored = try? await FamilyAPI().myFamilyToken() {
            AppConfig.storeFamilyToken(restored)
        }
        guard AppConfig.hasFamily else {
            stage = .setup
            return
        }
        if socketToken != AppConfig.familyToken {
            let hadSocket = !socketToken.isEmpty
            socketToken = AppConfig.familyToken
            if hadSocket {
                liveEpoch += 1
                return
            }
        }
        do {
            let snapshot = try await service.todaySnapshot()
            if snapshot.isWaitingParent {
                parent = snapshot.parent
                stage = .waiting(inviteCode: snapshot.inviteCode)
                return
            }
            // Weeks load in parallel BEFORE anything is published: one state
            // batch means one layout pass instead of a card that lands empty
            // and then jumps as each strip trickles in.
            let members = [snapshot.parent] + snapshot.others.map(\.parent)
            let loadedWeeks = await withTaskGroup(of: (UUID, [WeekDayResult])?.self) { group in
                for member in members {
                    group.addTask {
                        guard let results = try? await service.weekResults(
                            parentId: member.id, timezone: member.timezone
                        ) else { return nil }
                        return (member.id, results)
                    }
                }
                var collected: [UUID: [WeekDayResult]] = [:]
                for await pair in group {
                    if let (id, results) = pair { collected[id] = results }
                }
                return collected
            }
            parent = snapshot.parent
            stage = .ready
            status = snapshot.status
            streak = snapshot.streak
            medicationsTaken = snapshot.medsTaken
            medicationsTotal = snapshot.medsTotal
            evening = snapshot.evening
            upcomingDate = snapshot.upcomingDate
            others = snapshot.others
            weeks = loadedWeeks
            week = loadedWeeks[snapshot.parent.id] ?? week
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if stage == .loading {
                stage = .failed
            }
        }
    }

    func observeUpdates(_ updates: any FamilyLiveUpdates, reloadUsing service: any CheckinService) async {
        for await _ in await updates.stream() {
            await load(using: service)
        }
    }

    // MARK: Family Creation

    func createFamily() async {
        guard !isCreatingFamily, let city = selectedCity else { return }
        isCreatingFamily = true
        setupError = false
        defer { isCreatingFamily = false }
        do {
            let created = try await FamilyAPI().createFamily(
                momName: momName,
                momCity: city.displayName,
                momTimezone: city.timezone,
                checkinTime: checkinTime,
                childName: childName,
                childGender: childGender,
                botLanguage: botLang
            )
            AppConfig.storeFamilyToken(created.appToken.uuidString.lowercased())
            stage = .waiting(inviteCode: created.inviteCode)
            liveEpoch += 1
        } catch {
            setupError = true
        }
    }

    func inviteURL(code: String?) -> URL? {
        guard let code else { return nil }
        return URL(string: "https://t.me/\(AppConfig.botHandle)?start=inv_\(code)")
    }

    func refreshInvite() async {
        guard case .waiting = stage, !isCreatingFamily else { return }
        isCreatingFamily = true
        defer { isCreatingFamily = false }
        if let code = try? await FamilyAPI().newInviteCode() {
            stage = .waiting(inviteCode: code)
        }
    }

    // MARK: Derived

    var showsMedications: Bool {
        guard case .ready = stage else { return false }
        return medicationsTotal > 0
    }    

    var dateLine: String {
        let line = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale))
        return line.prefix(1).uppercased() + line.dropFirst()
    }

}
