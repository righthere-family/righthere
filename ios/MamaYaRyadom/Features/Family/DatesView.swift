import SwiftUI

// MARK: - Important Dates

struct DatesView: View {
    @State private var model = DatesViewModel()
    @State private var isShowingPaywall = false
    @State private var dateToRemove: FamilyDate?
    @State private var isConfirmingRemoval = false
    private let purchases = PurchaseModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.datesHint)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineSpacing(3)

                ForEach(model.dates) { date in
                    dateRow(date)
                }

                if purchases.hasSubscription {
                    addCard
                } else {
                    PremiumHintCard(
                        title: L10n.datesPremium,
                        hint: L10n.datesPremiumHint
                    ) {
                        isShowingPaywall = true
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Palette.background)
        .navigationTitle(L10n.datesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            await purchases.load()
        }
        .sheet(isPresented: $isShowingPaywall) { PaywallSheet() }
        .confirmDialog(
            L10n.confirmRemoveTitle(dateToRemove?.title ?? ""),
            actionTitle: L10n.confirmRemoveAction,
            isPresented: $isConfirmingRemoval
        ) {
            guard let date = dateToRemove else { return }
            Task { await model.remove(date) }
        }
    }

    private func dateRow(_ date: FamilyDate) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d.%02d", date.day, date.month))
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Palette.accent)
            Text(date.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer()
            Button {
                dateToRemove = date
                isConfirmingRemoval = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSecondary.opacity(0.6))
                    .padding(4)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Palette.card, in: .rect(cornerRadius: 18))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }

    private var localizedMonths: [String] {
        var calendar = Calendar.current
        calendar.locale = L10n.locale
        return calendar.standaloneMonthSymbols
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormUnderlineField(
                label: L10n.datesTitle,
                placeholder: L10n.datesPlaceholder,
                text: Bindable(model).newTitle
            )

            HStack(spacing: 18) {
                Picker("", selection: Bindable(model).newDay) {
                    ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("", selection: Bindable(model).newMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(localizedMonths[month - 1]).tag(month)
                    }
                }
                Spacer()
            }
            .pickerStyle(.menu)
            .tint(Palette.ink)
            .padding(.top, 10)

            FormPrimaryButton(
                title: L10n.datesAdd,
                isEnabled: model.canAdd,
                isBusy: model.isAdding
            ) {
                Task { await model.add() }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }
}

// MARK: - View Model

@Observable
@MainActor
final class DatesViewModel {
    private(set) var dates: [FamilyDate] = []
    private(set) var isAdding = false
    var newTitle = ""
    var newDay = 1
    var newMonth = 1

    var canAdd: Bool {
        !newTitle.trimmingCharacters(in: .whitespaces).isEmpty && !isAdding
    }

    func load() async {
        dates = (try? await FamilyAPI().dates()) ?? []
    }

    func add() async {
        guard canAdd else { return }
        isAdding = true
        defer { isAdding = false }
        guard (try? await FamilyAPI().addDate(title: newTitle, month: newMonth, day: newDay)) != nil else {
            return
        }
        newTitle = ""
        await load()
    }

    func remove(_ date: FamilyDate) async {
        try? await FamilyAPI().deleteDate(id: date.id)
        await load()
    }
}

#Preview {
    NavigationStack { DatesView() }
}
