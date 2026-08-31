import SwiftUI

// MARK: - Settings

// Everything that is about this device and this account, not about the
// family: subscription, language, policy, and the account-deletion door
// App Review requires (guideline 5.1.1(v)).
struct SettingsView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage("appLanguage") private var appLanguage = ""
    @AppStorage("appTheme") private var appTheme = "light"
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var role: String?
    @State private var isConfirmingDeletion = false
    @State private var isDeleting = false
    @State private var deleteFailed = false
    private let purchases = PurchaseModel.shared

    private var isSibling: Bool { role == "sibling" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                subscriptionRow
                languageRow
                themeRow
                privacyRow

                deleteRow
                    .padding(.top, 18)
                if deleteFailed {
                    Text(L10n.settingsDeleteFailed)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.alert)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Palette.background)
        .navigationTitle(L10n.routeSettings)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await purchases.load()
            role = try? await FamilyAPI().myRole()
        }
        .confirmDialog(
            isSibling ? L10n.settingsLeaveConfirm : L10n.settingsDeleteConfirm,
            message: isSibling ? L10n.settingsLeaveMessage : L10n.settingsDeleteMessage,
            actionTitle: isSibling ? L10n.settingsLeaveAction : L10n.confirmRemoveAction,
            isPresented: $isConfirmingDeletion
        ) {
            Task { await deleteAccount() }
        }
    }

    // MARK: - Rows

    private var subscriptionRow: some View {
        Button {
            router.push(.paywall)
        } label: {
            row(L10n.familySubscription) {
                Text(subscriptionStatus)
                    .font(.system(size: 13))
                    .foregroundStyle(purchases.hasSubscription ? Palette.okStrong : Palette.inkSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    // Names of the languages stay in their own tongue on purpose: the switch
    // must be findable when the app speaks a language you do not read.
    private var languageRow: some View {
        Menu {
            Button(L10n.familyLanguageSystem) { appLanguage = "" }
            Button("Русский") { appLanguage = "ru" }
            Button("English") { appLanguage = "en" }
        } label: {
            row(L10n.familyLanguage) {
                pickerValue(languageLabel)
            }
        }
        .buttonStyle(.plain)
    }

    private var themeRow: some View {
        Menu {
            Button(L10n.themeLight) { appTheme = "light" }
            Button(L10n.themeDark) { appTheme = "dark" }
            Button(L10n.themeSystem) { appTheme = "" }
        } label: {
            row(L10n.settingsTheme) {
                pickerValue(themeLabel)
            }
        }
        .buttonStyle(.plain)
    }

    private func pickerValue(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: 14))
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11))
        }
        .foregroundStyle(Palette.accent)
    }

    private var privacyRow: some View {
        Link(destination: URL(string: "https://righthere.family/privacy")!) {
            row(L10n.settingsPrivacy) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.accent.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    private var deleteRow: some View {
        Button {
            isConfirmingDeletion = true
        } label: {
            Group {
                if isDeleting {
                    ProgressView().tint(Palette.alert)
                } else {
                    Text(isSibling ? L10n.settingsLeave : L10n.settingsDelete)
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(Palette.alert)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
    }

    private func row(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }

    private var languageLabel: String {
        switch appLanguage {
        case "ru": "Русский"
        case "en": "English"
        default: L10n.familyLanguageSystem
        }
    }

    private var themeLabel: String {
        switch appTheme {
        case "light": L10n.themeLight
        case "dark": L10n.themeDark
        default: L10n.themeSystem
        }
    }

    private var subscriptionStatus: String {
        guard let id = purchases.purchasedIDs.first else { return L10n.subscriptionFreePlan }
        let name = switch id {
        case "ryadom.premium.monthly": L10n.paywallMonthly
        case "ryadom.premium.yearly": L10n.paywallYearly
        default: L10n.paywallFamily
        }
        return L10n.subscriptionYourPlan(name)
    }

    // MARK: - Deletion

    private func deleteAccount() async {
        isDeleting = true
        deleteFailed = false
        defer { isDeleting = false }
        let result = try? await FamilyAPI().deleteAccount()
        guard result == "deleted" || result == "left" else {
            deleteFailed = true
            return
        }
        try? await SupabaseHub.client?.auth.signOut()
        AppConfig.clearFamily()
        router.popToRoot()
        onboardingDone = false
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppRouter())
}
