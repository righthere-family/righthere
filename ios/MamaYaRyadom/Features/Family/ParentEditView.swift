import SwiftUI

// MARK: - Parent Edit

struct ParentEditView: View {
    static let eveningOptions = ["19:00", "20:00", "21:00", "22:00"]

    let parentId: UUID?
    @State private var isShowingPaywall = false
    private let purchases = PurchaseModel.shared
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var model = ParentEditViewModel()
    @State private var isConfirmingRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.isWaiting {
                    inviteBlock
                        .padding(.bottom, 24)
                }

                FormUnderlineField(
                    label: L10n.formName(kind: model.kind),
                    placeholder: L10n.setupMomNamePlaceholder,
                    text: Bindable(model).name
                )

                FormUnderlineField(
                    label: L10n.editMomPhone,
                    placeholder: L10n.editMomPhonePlaceholder,
                    text: Bindable(model).phone,
                    keyboard: .phonePad
                )
                .padding(.top, 22)

                FormUnderlineField(
                    label: L10n.formCity(kind: model.kind),
                    placeholder: L10n.setupCityPlaceholder,
                    text: Bindable(model).cityQuery
                )
                .padding(.top, 22)
                .autocorrectionDisabled()
                .onChange(of: model.cityQuery) { _, _ in
                    model.cityQueryEdited()
                }

                if !model.citySuggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(model.citySuggestions) { city in
                            Button {
                                model.choose(city)
                            } label: {
                                CityMatchRow(match: city)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Palette.background.opacity(0.6), in: .rect(cornerRadius: 12))
                    .padding(.top, 4)
                }

                if !model.isCityResolved {
                    Text(L10n.formCityPickHint)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, 8)
                }

                FormUnderlineValue(label: L10n.formMorning, value: model.checkinTime, monospaced: true) {
                    ForEach(TodayViewModel.timeOptions, id: \.self) { time in
                        Button(time) { model.checkinTime = time }
                    }
                }
                .padding(.top, 22)

                FormUnderlineValue(
                    label: L10n.windowLabel,
                    value: L10n.windowHours(model.windowMinutes / 60),
                    monospaced: true
                ) {
                    ForEach([120, 180, 240], id: \.self) { minutes in
                        Button(L10n.windowHours(minutes / 60)) {
                            model.pickWindow(minutes, premium: purchases.hasSubscription)
                        }
                    }
                }
                .padding(.top, 22)

                FormUnderlineValue(
                    label: L10n.eveningLabel,
                    value: model.eveningTime ?? L10n.eveningOff,
                    monospaced: model.eveningTime != nil
                ) {
                    Button(L10n.eveningOff) { model.pickEvening(nil, premium: purchases.hasSubscription) }
                    ForEach(Self.eveningOptions, id: \.self) { time in
                        Button(time) { model.pickEvening(time, premium: purchases.hasSubscription) }
                    }
                }
                .padding(.top, 22)

                // Language names stay in their own tongue, like the app switch.
                FormUnderlineValue(
                    label: L10n.formBotLanguage,
                    value: model.botLang == "en" ? "English" : "Русский"
                ) {
                    Button("Русский") { model.botLang = "ru" }
                    Button("English") { model.botLang = "en" }
                }
                .padding(.top, 22)

                if model.saveFailed {
                    Text(L10n.setupError)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.alert)
                        .padding(.top, 12)
                }

                FormPrimaryButton(
                    title: L10n.medsSave,
                    isEnabled: model.canSave,
                    isBusy: model.isSaving
                ) {
                    Task {
                        if await model.save() {
                            dismiss()
                        }
                    }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(Palette.card, in: .rect(cornerRadius: 24))
            .shadow(color: Palette.ink.opacity(0.05), radius: 16, y: 6)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            removeButton
        }
        .background(Palette.background)
        .navigationTitle(L10n.editTitle(kind: model.kind))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load(parentId: parentId, using: dependencies.checkinService)
            await purchases.load()
        }
        .sheet(isPresented: $isShowingPaywall) { PaywallSheet() }
        .onChange(of: model.wantsPaywall) { _, wants in
            if wants {
                isShowingPaywall = true
                model.paywallShown()
            }
        }
    }

    // MARK: - Invite

    private var inviteBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.familyMomWaiting)
                .font(Typography.display(20))
                .foregroundStyle(Palette.ink)

            Text(L10n.waitingText(kind: model.kind))
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkSecondary)
                .lineSpacing(3)

            if let url = model.inviteURL {
                ShareLink(item: url) {
                    inviteButtonLabel(Text(L10n.waitingShare(kind: model.kind)))
                }
            } else {
                Button {
                    Task { await model.refreshInvite() }
                } label: {
                    inviteButtonLabel(
                        model.isRefreshingInvite ? nil : Text(L10n.waitingNewLink)
                    )
                }
                .disabled(model.isRefreshingInvite)
            }

            Text(L10n.waitingHint(kind: model.kind))
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.inkSecondary.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inviteButtonLabel(_ title: Text?) -> some View {
        Group {
            if let title {
                Label { title } icon: { Image(systemName: "paperplane.fill") }
            } else {
                ProgressView().tint(.white)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Palette.accent, in: .rect(cornerRadius: 14))
    }

    // MARK: - Remove

    @ViewBuilder
    private var removeButton: some View {
        if model.canRemove {
            Button(role: .destructive) {
                isConfirmingRemoval = true
            } label: {
                Text(L10n.familyRemoveParent)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.alert)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .padding(.top, 8)
            .confirmDialog(
                L10n.familyRemoveConfirm(model.name),
                actionTitle: L10n.familyRemoveAction,
                isPresented: $isConfirmingRemoval
            ) {
                Task {
                    if await model.remove() { dismiss() }
                }
            }
        }
    }

}

// MARK: - View Model

@Observable
@MainActor
final class ParentEditViewModel {
    var name = ""
    var phone = ""
    var cityQuery = ""
    var selectedCity: City?
    var checkinTime = "09:00"
    var botLang = "ru"
    private(set) var isWaiting = false
    private(set) var inviteCode: String?
    private(set) var isRefreshingInvite = false
    private(set) var isSaving = false
    private(set) var saveFailed = false
    private var timezone = "Europe/Moscow"

    let citySearch = CitySearch()

    var citySuggestions: [CitySearch.Match] {
        guard selectedCity == nil else { return [] }
        return citySearch.matches
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && isCityResolved && !isSaving
    }

    var isCityResolved: Bool {
        selectedCity != nil || cityQuery == loadedCity
    }

    func choose(_ match: CitySearch.Match) {
        Task {
            guard let city = await citySearch.resolve(match) else { return }
            selectedCity = city
            timezone = city.timezone
            cityQuery = match.title
            citySearch.clear()
        }
    }

    func cityQueryEdited() {
        if let selected = selectedCity {
            guard !selected.matches(cityQuery) else {
                citySearch.clear()
                return
            }
            selectedCity = nil
        }
        guard cityQuery != loadedCity else {
            citySearch.clear()
            return
        }
        citySearch.update(query: cityQuery)
    }

    private var loadedCity = ""

    private(set) var parentId: UUID?
    private(set) var canRemove = false
    private(set) var kind: Parent.Kind = .mom
    private(set) var eveningTime: String?
    private(set) var eveningChanged = false
    private(set) var windowMinutes = 180
    private(set) var windowChanged = false
    private(set) var wantsPaywall = false

    func load(parentId: UUID?, using service: any CheckinService) async {
        self.parentId = parentId
        guard let snapshot = try? await service.todaySnapshot() else { return }
        let member = snapshot.everyone.first { $0.parent.id == parentId } ?? snapshot
        // The last parent cannot be removed, so the button never appears for them.
        canRemove = snapshot.everyone.count > 1
        isWaiting = member.isWaitingParent
        inviteCode = member.inviteCode
        kind = member.parent.kind
        eveningTime = member.parent.eveningTime
        windowMinutes = member.parent.windowMinutes
        name = member.parent.displayName
        phone = member.parent.phone ?? ""
        loadedCity = member.parent.cityName
        cityQuery = member.parent.cityName
        timezone = member.parent.timezone
        checkinTime = member.parent.checkinTime
        botLang = member.parent.botLanguage
        selectedCity = City.all.first { $0.matches(member.parent.cityName) }
    }

    var inviteURL: URL? {
        guard let inviteCode else { return nil }
        return URL(string: "https://t.me/\(AppConfig.botHandle)?start=inv_\(inviteCode)")
    }

    func refreshInvite() async {
        guard let parentId, !isRefreshingInvite else { return }
        isRefreshingInvite = true
        defer { isRefreshingInvite = false }
        inviteCode = try? await FamilyAPI().parentInviteCode(parentId: parentId)
    }

    func pickWindow(_ minutes: Int, premium: Bool) {
        guard minutes != windowMinutes else { return }
        if !premium {
            wantsPaywall = true
            return
        }
        windowMinutes = minutes
        windowChanged = true
    }

    func pickEvening(_ time: String?, premium: Bool) {
        // Turning the evening question ON is the premium act; turning it off
        // must always work.
        if time != nil && !premium {
            wantsPaywall = true
            return
        }
        eveningTime = time
        eveningChanged = true
    }

    func paywallShown() {
        wantsPaywall = false
    }

    func remove() async -> Bool {
        guard let parentId else { return false }
        return (try? await FamilyAPI().removeParent(id: parentId)) ?? false
    }

    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        let isCityChanged = cityQuery != loadedCity
        let city = isCityChanged ? (selectedCity?.displayName ?? cityQuery) : loadedCity
        let tz = isCityChanged ? (selectedCity?.timezone ?? timezone) : timezone
        do {
            try await FamilyAPI().updateParent(
                name: name,
                city: city,
                timezone: tz,
                checkinTime: checkinTime,
                phone: phone,
                parentId: parentId,
                botLanguage: botLang
            )
            if eveningChanged, let parentId {
                _ = try? await FamilyAPI().setEveningTime(parentId: parentId, time: eveningTime)
            }
            if windowChanged, let parentId {
                _ = try? await FamilyAPI().setWindow(parentId: parentId, minutes: windowMinutes)
            }
            return true
        } catch {
            saveFailed = true
            return false
        }
    }
}

#Preview {
    NavigationStack { ParentEditView(parentId: nil) }
        .environment(AppRouter())
}
