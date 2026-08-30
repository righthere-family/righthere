import Foundation
import Observation

// MARK: - View Model

@Observable
@MainActor
final class MedsViewModel {
    struct Slot: Identifiable {
        let id = UUID()
        var time: Date
    }

    private(set) var meds: [MedInfo] = []
    private(set) var isSaving = false
    private(set) var editingMed: MedInfo?
    var newTitle = ""
    var slots: [Slot] = [Slot(time: MedsViewModel.defaultSlot)]

    static var defaultSlot: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    }

    private static var slotFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    var canSave: Bool {
        !newTitle.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    private(set) var parentId: UUID?

    func load(parentId: UUID?) async {
        self.parentId = parentId
        meds = (try? await FamilyAPI().meds(parentId: parentId)) ?? []
    }

    func addSlot() {
        guard slots.count < 4 else { return }
        slots.append(Slot(time: Self.defaultSlot))
    }

    func removeSlot(_ slot: Slot) {
        guard slots.count > 1 else { return }
        slots.removeAll { $0.id == slot.id }
    }

    func beginEdit(_ med: MedInfo) {
        editingMed = med
        newTitle = med.title
        let formatter = Self.slotFormatter
        slots = med.times.compactMap { formatter.date(from: $0) }.map { Slot(time: $0) }
        if slots.isEmpty {
            slots = [Slot(time: Self.defaultSlot)]
        }
    }

    func cancelEdit() {
        editingMed = nil
        newTitle = ""
        slots = [Slot(time: Self.defaultSlot)]
    }

    func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        let formatter = Self.slotFormatter
        let times = slots.map { formatter.string(from: $0.time) }
        if let editing = editingMed {
            guard (try? await FamilyAPI().updateMed(id: editing.id, title: newTitle, times: times)) != nil else {
                return
            }
        } else {
            guard (try? await FamilyAPI().addMed(title: newTitle, times: times, parentId: parentId)) != nil else {
                return
            }
        }
        cancelEdit()
        await load(parentId: parentId)
    }

    func remove(_ med: MedInfo) async {
        try? await FamilyAPI().deleteMed(id: med.id)
        await load(parentId: parentId)
    }
}
