import AppIntents
import WidgetKit

// MARK: - Parent Choice

// A small widget holds one parent. Left unset, it keeps showing the first one
// and the medium size lists the whole family; pick somebody and both sizes
// become about them, so a family can keep one widget per parent.
struct ParentChoice: AppEntity, Identifiable, Hashable {
    let id: String
    let name: String

    static let defaultQuery = ParentChoiceQuery()

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("widget.pick.type"))
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ParentChoiceQuery: EntityQuery {
    func entities(for identifiers: [ParentChoice.ID]) async throws -> [ParentChoice] {
        known().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ParentChoice] {
        known()
    }

    // The list comes from the snapshot the app and the widget already share,
    // so the picker opens instantly and works offline.
    private func known() -> [ParentChoice] {
        guard let snapshot = SharedStore.cachedSnapshot.flatMap(WidgetSnapshot.decode) else { return [] }
        return snapshot.members.map { ParentChoice(id: $0.parent.id, name: $0.parent.displayName) }
    }
}

struct SelectParent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "widget.pick.title"
    static let description = IntentDescription(LocalizedStringResource("widget.pick.description"))

    @Parameter(title: "widget.pick.parameter")
    var parent: ParentChoice?
}
