import SwiftUI

// MARK: - Add Parent

struct AddParentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = AddParentViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let invite = model.inviteURL {
                    ready(invite: invite)
                } else {
                    form
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .background(Palette.background)
        .navigationTitle(L10n.familyAddParent)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.familyAddParentHint)
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkSecondary)
                .lineSpacing(3)

            kindPicker
                .padding(.top, 18)

            FormUnderlineField(
                label: L10n.formName(kind: model.kind.parentKind),
                placeholder: model.kind.namePlaceholder,
                text: Bindable(model).name
            )
            .padding(.top, 24)

            FormUnderlineField(
                label: L10n.formCity(kind: model.kind.parentKind),
                placeholder: L10n.setupCityPlaceholder,
                text: Bindable(model).cityQuery
            )
            .padding(.top, 22)
            suggestions

            FormUnderlineValue(label: L10n.formMorning, value: model.checkinTime, monospaced: true) {
                ForEach(TodayViewModel.timeOptions, id: \.self) { time in
                    Button(time) { model.checkinTime = time }
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

            FormPrimaryButton(
                title: L10n.setupCreate,
                isEnabled: model.canCreate,
                isBusy: model.isCreating
            ) {
                Task { await model.create() }
            }
            .padding(.top, 26)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(Palette.card, in: .rect(cornerRadius: 22))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(AddParentViewModel.Kind.allCases) { kind in
                Button {
                    model.kind = kind
                } label: {
                    Text(kind.title)
                        .font(.system(size: 14, weight: model.kind == kind ? .semibold : .regular))
                        .foregroundStyle(model.kind == kind ? .white : Palette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            model.kind == kind ? Palette.accent : Palette.background,
                            in: .capsule
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.citySuggestions) { city in
                Button {
                    model.choose(city)
                } label: {
                    CityMatchRow(match: city)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if city != model.citySuggestions.last {
                    Divider().overlay(Palette.inkSecondary.opacity(0.15))
                }
            }
        }
        .padding(.horizontal, 12)
        .background(Palette.background, in: .rect(cornerRadius: 12))
        .padding(.top, model.citySuggestions.isEmpty ? 0 : 8)
    }

    // MARK: - Ready

    private func ready(invite: URL) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.familyNewInviteReady)
                .font(.system(size: 15))
                .foregroundStyle(Palette.inkSecondary)
                .lineSpacing(3)

            ShareLink(item: L10n.familyInviteMessage(invite.absoluteString)) {
                Label(L10n.waitingShare, systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.accent, in: .rect(cornerRadius: 14))
            }
            .padding(.top, 18)

            Button(L10n.postcardCancel) { dismiss() }
                .font(.system(size: 14))
                .foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(Palette.card, in: .rect(cornerRadius: 22))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }

}

// MARK: - View Model

@Observable
@MainActor
final class AddParentViewModel {
    enum Kind: String, CaseIterable, Identifiable {
        case mom
        case dad
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mom: L10n.familyParentKindMom
            case .dad: L10n.familyParentKindDad
            case .custom: L10n.familyParentKindCustom
            }
        }

        var parentKind: Parent.Kind {
            Parent.Kind(rawValue: rawValue) ?? .custom
        }

        var namePlaceholder: String {
            switch self {
            case .mom: L10n.familyParentKindMom
            case .dad: L10n.familyParentKindDad
            case .custom: ""
            }
        }
    }

    var kind: Kind = .dad
    var name = ""
    var cityQuery = "" {
        didSet {
            guard selectedCity?.matches(cityQuery) != true else { return }
            selectedCity = nil
            citySearch.update(query: cityQuery)
        }
    }
    var checkinTime = "09:00"
    var botLang = L10n.effectiveLanguage
    private(set) var isCreating = false
    private(set) var inviteURL: URL?
    private var selectedCity: City?
    let citySearch = CitySearch()

    var citySuggestions: [CitySearch.Match] {
        guard selectedCity == nil else { return [] }
        return citySearch.matches
    }

    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedCity != nil && !isCreating
    }

    func choose(_ match: CitySearch.Match) {
        Task {
            // Resolve first: clearing drops the completion the resolve needs.
            selectedCity = await citySearch.resolve(match)
            cityQuery = match.title
            citySearch.clear()
        }
    }

    func create() async {
        guard canCreate, let city = selectedCity else { return }
        isCreating = true
        defer { isCreating = false }
        guard let added = try? await FamilyAPI().addParent(
            name: name,
            kind: kind.rawValue,
            city: city.displayName,
            timezone: city.timezone,
            checkinTime: checkinTime,
            botLanguage: botLang
        ) else {
            return
        }
        inviteURL = URL(string: "https://t.me/\(AppConfig.botHandle)?start=inv_\(added.inviteCode)")
    }
}

#Preview {
    NavigationStack { AddParentView() }
}
