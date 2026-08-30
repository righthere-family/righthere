import Foundation
import MapKit
import Observation

// MARK: - City Search

@Observable
@MainActor
final class CitySearch: NSObject, MKLocalSearchCompleterDelegate {
    struct Match: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let local: City?
    }

    private(set) var matches: [Match] = []
    private let completer = MKLocalSearchCompleter()
    private var remote: [MKLocalSearchCompletion] = []
    private var query = ""

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(query: String) {
        self.query = query
        guard query.count >= 2 else {
            remote = []
            matches = []
            completer.queryFragment = ""
            return
        }
        rebuild()
        completer.queryFragment = query
    }

    func clear() {
        update(query: "")
    }

    func resolve(_ match: Match) async -> City? {
        if let local = match.local {
            return local
        }
        guard let completion = remote.first(where: { Self.key(for: $0) == match.id }) else {
            return nil
        }
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
        guard let response = try? await search.start(),
              let timezone = response.mapItems.first?.timeZone?.identifier else {
            return nil
        }
        return City(ru: match.title, en: match.title, timezone: timezone)
    }

    // MARK: - Merge

    private func rebuild() {
        let locals = City.search(query, limit: 3).map { city in
            Match(id: "local-\(city.id)", title: city.displayName, subtitle: "", local: city)
        }
        let known = Set(locals.map { $0.title.lowercased() })
        let extras = remote
            .filter { !known.contains($0.title.lowercased()) }
            .prefix(5)
            .map { Match(id: Self.key(for: $0), title: $0.title, subtitle: $0.subtitle, local: nil) }
        matches = locals + extras
    }

    private static func key(for completion: MKLocalSearchCompletion) -> String {
        "remote-\(completion.title)|\(completion.subtitle)"
    }

    // MARK: - MKLocalSearchCompleterDelegate

    // MKLocalSearchCompleter documents that delegate methods arrive on the
    // main queue, which makes assumeIsolated the honest bridge into MainActor.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        nonisolated(unsafe) let results = completer.results
        MainActor.assumeIsolated {
            remote = results
            rebuild()
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            remote = []
            rebuild()
        }
    }
}
