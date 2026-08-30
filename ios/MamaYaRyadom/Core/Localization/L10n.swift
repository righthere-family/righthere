import Foundation

// MARK: - Localized Strings

enum L10n {
    // MARK: Language Override

    // "" follows the system; "ru"/"en" pin the app language. Views re-render
    // via RootView's .id(...) on change, so strings resolve lazily each time.
    static var languageOverride: String {
        get { UserDefaults.standard.string(forKey: "appLanguage") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "appLanguage") }
    }

    static var locale: Locale {
        languageOverride.isEmpty ? .autoupdatingCurrent : Locale(identifier: languageOverride)
    }

    static var bundle: Bundle {
        guard !languageOverride.isEmpty,
              let path = Bundle.main.path(forResource: languageOverride, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    // The concrete two-letter code the UI is speaking right now — the default
    // bot language for a newly created parent and the push language sent with
    // the APNs token.
    static var effectiveLanguage: String {
        if !languageOverride.isEmpty { return languageOverride }
        return (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("ru") ? "ru" : "en"
    }

    // MARK: Tabs

    static var tabToday: String { String(localized: "tab.today", bundle: bundle) }
    static var tabHistory: String { String(localized: "tab.history", bundle: bundle) }
    static var tabFamily: String { String(localized: "tab.family", bundle: bundle) }

    // MARK: Statuses

    static var statusAllGood: String { String(localized: "status.allGood", bundle: bundle) }
    static var statusStillMorning: String { String(localized: "status.stillMorning", bundle: bundle) }
    static var statusReminded: String { String(localized: "status.reminded", bundle: bundle) }
    static var statusQuiet: String { String(localized: "status.quiet", bundle: bundle) }
    static var statusQuietHint: String { String(localized: "status.quietHint", bundle: bundle) }
    static var statusNotOkGeneric: String { String(localized: "status.notOk.generic", bundle: bundle) }
    static var statusNotOkHealth: String { String(localized: "status.notOk.health", bundle: bundle) }
    static var statusNotOkMood: String { String(localized: "status.notOk.mood", bundle: bundle) }
    static var statusNotOkJustDay: String { String(localized: "status.notOk.justDay", bundle: bundle) }
    static var statusNotOkCallMe: String { String(localized: "status.notOk.callMe", bundle: bundle) }
    static var statusPaused: String { String(localized: "status.paused", bundle: bundle) }

    static func statusTodayAt(_ time: String, _ city: String) -> String {
        String(format: String(localized: "status.todayAt", bundle: bundle), time, city)
    }

    static func statusUsuallyBy(_ time: String) -> String {
        String(format: String(localized: "status.usuallyBy", bundle: bundle), time)
    }

    static func statusWaitingUntil(_ time: String) -> String {
        String(format: String(localized: "status.waitingUntil", bundle: bundle), time)
    }

    static func statusPausedUntil(_ date: String) -> String {
        String(format: String(localized: "status.pausedUntil", bundle: bundle), date)
    }

    static func statusStreak(_ count: Int) -> String {
        String(format: String(localized: "status.streak", bundle: bundle), count)
    }

    static var statusHerWords: String { String(localized: "status.herWords", bundle: bundle) }

    static func parentQuote(_ name: String, _ quote: String) -> String {
        String(format: String(localized: "parent.quote", bundle: bundle), name, quote)
    }

    // MARK: Today

    static var todayTitle: String { String(localized: "today.title", bundle: bundle) }
    static var todayCallMom: String { String(localized: "today.callMom", bundle: bundle) }
    static var todayMedications: String { String(localized: "today.medications", bundle: bundle) }

    static func todayMedicationsTaken(_ taken: Int, _ total: Int) -> String {
        String(format: String(localized: "today.medicationsTaken", bundle: bundle), taken, total)
    }

    static func todaySiblingHint(_ name: String) -> String {
        String(format: String(localized: "today.siblingHint", bundle: bundle), name)
    }

    // MARK: Onboarding

    static var onboardingSlide1Title: String { String(localized: "onboarding.slide1.title", bundle: bundle) }
    static var onboardingSlide1Text: String { String(localized: "onboarding.slide1.text", bundle: bundle) }
    static var onboardingSlide2Title: String { String(localized: "onboarding.slide2.title", bundle: bundle) }
    static var onboardingSlide2Text: String { String(localized: "onboarding.slide2.text", bundle: bundle) }
    static var onboardingSlide3Title: String { String(localized: "onboarding.slide3.title", bundle: bundle) }
    static var onboardingSlide3Text: String { String(localized: "onboarding.slide3.text", bundle: bundle) }
    static var onboardingContinue: String { String(localized: "onboarding.continue", bundle: bundle) }
    static var onboardingStart: String { String(localized: "onboarding.start", bundle: bundle) }
    static var onboardingSceneOk: String { String(localized: "onboarding.scene.ok", bundle: bundle) }
    static var onboardingSceneButton: String { String(localized: "onboarding.scene.button", bundle: bundle) }
    static var onboardingStoryDistance: String { String(localized: "onboarding.story.distance", bundle: bundle) }
    static var onboardingStoryButton: String { String(localized: "onboarding.story.button", bundle: bundle) }
    static var onboardingStoryDelivered: String { String(localized: "onboarding.story.delivered", bundle: bundle) }
    static var onboardingStoryHabit: String { String(localized: "onboarding.story.habit", bundle: bundle) }
    static var onboardingStoryPrivacy: String { String(localized: "onboarding.story.privacy", bundle: bundle) }
    static var onboardingStoryHint: String { String(localized: "onboarding.story.hint", bundle: bundle) }
    static var onboardingStoryHintButton: String { String(localized: "onboarding.story.hintButton", bundle: bundle) }
    static var onboardingLabelMom: String { String(localized: "onboarding.label.mom", bundle: bundle) }
    static var onboardingLabelYou: String { String(localized: "onboarding.label.you", bundle: bundle) }
    static var onboardingPhoneBotName: String { String(localized: "onboarding.phone.botName", bundle: bundle) }
    static var onboardingPhoneGreeting: String { String(localized: "onboarding.phone.greeting", bundle: bundle) }
    static var onboardingPhoneNotOk: String { String(localized: "onboarding.phone.notOk", bundle: bundle) }
    static var onboardingWidgetWho: String { String(localized: "onboarding.widget.who", bundle: bundle) }
    static var onboardingWidgetTime: String { String(localized: "onboarding.widget.time", bundle: bundle) }

    // MARK: Setup

    static var setupTitle: String { String(localized: "setup.title", bundle: bundle) }
    static var setupYourName: String { String(localized: "setup.yourName", bundle: bundle) }
    static var setupYourNamePlaceholder: String { String(localized: "setup.yourNamePlaceholder", bundle: bundle) }
    static var setupSon: String { String(localized: "setup.son", bundle: bundle) }
    static var setupDaughter: String { String(localized: "setup.daughter", bundle: bundle) }
    static var setupMomName: String { String(localized: "setup.momName", bundle: bundle) }
    static var setupMomNamePlaceholder: String { String(localized: "setup.momNamePlaceholder", bundle: bundle) }
    static var setupCity: String { String(localized: "setup.city", bundle: bundle) }
    static var setupCityPlaceholder: String { String(localized: "setup.cityPlaceholder", bundle: bundle) }
    static var setupTime: String { String(localized: "setup.time", bundle: bundle) }
    static var setupCreate: String { String(localized: "setup.create", bundle: bundle) }
    static var setupError: String { String(localized: "setup.error", bundle: bundle) }
    static var waitingTitle: String { String(localized: "waiting.title", bundle: bundle) }
    static var waitingText: String { String(localized: "waiting.text", bundle: bundle) }
    static var waitingShare: String { String(localized: "waiting.share", bundle: bundle) }
    static var waitingHint: String { String(localized: "waiting.hint", bundle: bundle) }
    static var waitingNewLink: String { String(localized: "waiting.newLink", bundle: bundle) }

    // MARK: Meds

    static var medsEmpty: String { String(localized: "meds.empty", bundle: bundle) }
    static var medsNewTitle: String { String(localized: "meds.newTitle", bundle: bundle) }
    static var medsNamePlaceholder: String { String(localized: "meds.namePlaceholder", bundle: bundle) }
    static var medsAddTime: String { String(localized: "meds.addTime", bundle: bundle) }
    static var medsAdd: String { String(localized: "meds.add", bundle: bundle) }
    static var medsEdit: String { String(localized: "meds.edit", bundle: bundle) }
    static var medsEditTitle: String { String(localized: "meds.editTitle", bundle: bundle) }
    static var medsCancel: String { String(localized: "meds.cancel", bundle: bundle) }
    static var medsSave: String { String(localized: "meds.save", bundle: bundle) }

    // MARK: Routes

    static var routeParentProfile: String { String(localized: "route.parentProfile", bundle: bundle) }
    static var routeMedications: String { String(localized: "route.medications", bundle: bundle) }
    static var routeEscalation: String { String(localized: "route.escalation", bundle: bundle) }
    static var routeInviteSibling: String { String(localized: "route.inviteSibling", bundle: bundle) }
    static var routePaywall: String { String(localized: "route.paywall", bundle: bundle) }
    static var routeSettings: String { String(localized: "route.settings", bundle: bundle) }

    // MARK: History

    static func historySummary(_ good: Int, _ total: Int) -> String {
        String(format: String(localized: "history.summary", bundle: bundle), good, total)
    }

    static var historyLegendHerWords: String { String(localized: "history.legend.herWords", bundle: bundle) }
    static var historyLegendQuiet: String { String(localized: "history.legend.quiet", bundle: bundle) }
    static var historyDayHerWords: String { String(localized: "history.day.herWords", bundle: bundle) }
    static var historyDayNoWord: String { String(localized: "history.day.noWord", bundle: bundle) }
    static var historyDayNoWordNote: String { String(localized: "history.day.noWordNote", bundle: bundle) }
    static var historyDayPausedNote: String { String(localized: "history.day.pausedNote", bundle: bundle) }

    // MARK: Family

    static var familyMomConnected: String { String(localized: "family.momConnected", bundle: bundle) }
    static var familyMomWaiting: String { String(localized: "family.momWaiting", bundle: bundle) }
    static var familyInviteTitle: String { String(localized: "family.invite.title", bundle: bundle) }
    static var familyInviteText: String { String(localized: "family.invite.text", bundle: bundle) }
    static var familyInviteButton: String { String(localized: "family.invite.button", bundle: bundle) }
    static var familySubscription: String { String(localized: "family.subscription", bundle: bundle) }
    static var familySubscriptionBeta: String { String(localized: "family.subscription.beta", bundle: bundle) }

    static func familyInviteMessage(_ link: String) -> String {
        String(format: String(localized: "family.invite.message", bundle: bundle), link)
    }

    // MARK: Paywall

    static var paywallBetaBadge: String { String(localized: "paywall.betaBadge", bundle: bundle) }
    static var paywallTitle: String { String(localized: "paywall.title", bundle: bundle) }
    static var paywallText: String { String(localized: "paywall.text", bundle: bundle) }
    static var paywallMonthly: String { String(localized: "paywall.monthly", bundle: bundle) }
    static var paywallYearly: String { String(localized: "paywall.yearly", bundle: bundle) }
    static var paywallFamily: String { String(localized: "paywall.family", bundle: bundle) }
    static var paywallSubscribe: String { String(localized: "paywall.subscribe", bundle: bundle) }
    static var paywallActive: String { String(localized: "paywall.active", bundle: bundle) }
    static var paywallCurrent: String { String(localized: "paywall.current", bundle: bundle) }
    static var paywallRestore: String { String(localized: "paywall.restore", bundle: bundle) }
    static var paywallDisclaimer: String { String(localized: "paywall.disclaimer", bundle: bundle) }
    static var paywallPending: String { String(localized: "paywall.pending", bundle: bundle) }
    static var paywallFailed: String { String(localized: "paywall.failed", bundle: bundle) }
    static var todayLoadFailed: String { String(localized: "today.loadFailed", bundle: bundle) }
    static var todayRetry: String { String(localized: "today.retry", bundle: bundle) }
    static var editMomTitle: String { String(localized: "edit.momTitle", bundle: bundle) }
    static var editMomName: String { String(localized: "edit.momName", bundle: bundle) }
    static var editMomPhone: String { String(localized: "edit.momPhone", bundle: bundle) }
    static var editMomPhonePlaceholder: String { String(localized: "edit.momPhonePlaceholder", bundle: bundle) }

    // MARK: Postcard

    static var postcardButton: String { String(localized: "postcard.button", bundle: bundle) }
    static var postcardPlaceholder: String { String(localized: "postcard.placeholder", bundle: bundle) }
    static var postcardSend: String { String(localized: "postcard.send", bundle: bundle) }
    static var postcardCancel: String { String(localized: "postcard.cancel", bundle: bundle) }
    static var postcardHint: String { String(localized: "postcard.hint", bundle: bundle) }
    static var postcardSent: String { String(localized: "postcard.sent", bundle: bundle) }
    static var postcardFailed: String { String(localized: "postcard.failed", bundle: bundle) }

    // Dynamic keys must go through Bundle.localizedString: interpolating into
    // String.LocalizationValue would make the KEY itself "form.name.%@".
    private static func dynamic(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func postcardTitle(kind: Parent.Kind) -> String {
        dynamic("postcard.title.\(kind.rawValue)")
    }

    static func postcardPlaceholder(kind: Parent.Kind) -> String {
        dynamic("postcard.placeholder.\(kind.rawValue)")
    }

    static func formName(kind: Parent.Kind) -> String {
        dynamic("form.name.\(kind.rawValue)")
    }

    static func formCity(kind: Parent.Kind) -> String {
        dynamic("form.city.\(kind.rawValue)")
    }

    static var formMorning: String { String(localized: "form.morning", bundle: bundle) }
    static var formBotLanguage: String { String(localized: "form.botLanguage", bundle: bundle) }

    static func editTitle(kind: Parent.Kind) -> String {
        dynamic("edit.title.\(kind.rawValue)")
    }

    // MARK: Family Members

    static var familyAddParent: String { String(localized: "family.addParent", bundle: bundle) }
    static var familyAddParentHint: String { String(localized: "family.addParentHint", bundle: bundle) }
    static var familyParents: String { String(localized: "family.parents", bundle: bundle) }
    static var familyNewInviteReady: String { String(localized: "family.newInviteReady", bundle: bundle) }
    static var familyParentKindMom: String { String(localized: "family.parentKindMom", bundle: bundle) }
    static var familyParentKindDad: String { String(localized: "family.parentKindDad", bundle: bundle) }
    static var familyParentKindCustom: String { String(localized: "family.parentKindCustom", bundle: bundle) }
    static var familyRemoveParent: String { String(localized: "family.removeParent", bundle: bundle) }
    static var familyRemoveAction: String { String(localized: "family.removeAction", bundle: bundle) }
    static var familyRemoveLast: String { String(localized: "family.removeLast", bundle: bundle) }

    static func windowHours(_ hours: Int) -> String {
        String(format: String(localized: "window.hours", bundle: bundle), hours)
    }

    static var messagesTitle: String { String(localized: "messages.title", bundle: bundle) }
    static var messagesRowHint: String { String(localized: "messages.rowHint", bundle: bundle) }
    static var messagesEmpty: String { String(localized: "messages.empty", bundle: bundle) }
    static var messagesVoice: String { String(localized: "messages.voice", bundle: bundle) }

    static var settingsPrivacy: String { String(localized: "settings.privacy", bundle: bundle) }
    static var settingsDelete: String { String(localized: "settings.delete", bundle: bundle) }
    static var settingsLeave: String { String(localized: "settings.leave", bundle: bundle) }
    static var settingsDeleteConfirm: String { String(localized: "settings.deleteConfirm", bundle: bundle) }
    static var settingsDeleteMessage: String { String(localized: "settings.deleteMessage", bundle: bundle) }
    static var settingsLeaveConfirm: String { String(localized: "settings.leaveConfirm", bundle: bundle) }
    static var settingsLeaveMessage: String { String(localized: "settings.leaveMessage", bundle: bundle) }
    static var settingsLeaveAction: String { String(localized: "settings.leaveAction", bundle: bundle) }
    static var settingsDeleteFailed: String { String(localized: "settings.deleteFailed", bundle: bundle) }

    static var familyLanguage: String { String(localized: "family.language", bundle: bundle) }
    static var familyLanguageSystem: String { String(localized: "family.languageSystem", bundle: bundle) }

    static func familyRemoveConfirm(_ name: String) -> String {
        String(format: String(localized: "family.removeConfirm", bundle: bundle), name)
    }

    // MARK: Confirm

    static var confirmRemoveAction: String { String(localized: "confirm.removeAction", bundle: bundle) }

    static func confirmRemoveTitle(_ what: String) -> String {
        String(format: String(localized: "confirm.removeTitle", bundle: bundle), what)
    }

    // MARK: Restore

    static var restoreTitle: String { String(localized: "restore.title", bundle: bundle) }
    static var restoreHint: String { String(localized: "restore.hint", bundle: bundle) }

    // MARK: Premium

    static var premiumParents: String { String(localized: "premium.parents", bundle: bundle) }
    static var premiumParentsHint: String { String(localized: "premium.parentsHint", bundle: bundle) }
    static var premiumMeds: String { String(localized: "premium.meds", bundle: bundle) }
    static var premiumMedsHint: String { String(localized: "premium.medsHint", bundle: bundle) }
    static var premiumHistory: String { String(localized: "premium.history", bundle: bundle) }
    static var premiumLearnMore: String { String(localized: "premium.learnMore", bundle: bundle) }
    static var premiumDone: String { String(localized: "premium.done", bundle: bundle) }
    static var paywallFeatureParents: String { String(localized: "paywall.feature.parents", bundle: bundle) }
    static var paywallFeatureMeds: String { String(localized: "paywall.feature.meds", bundle: bundle) }
    static var paywallFeatureHistory: String { String(localized: "paywall.feature.history", bundle: bundle) }
    static var paywallFeatureFamily: String { String(localized: "paywall.feature.family", bundle: bundle) }
    static var paywallSwitchPlan: String { String(localized: "paywall.switchPlan", bundle: bundle) }
    static var paywallManage: String { String(localized: "paywall.manage", bundle: bundle) }
    static var subscriptionFreePlan: String { String(localized: "subscription.freePlan", bundle: bundle) }

    static func subscriptionYourPlan(_ name: String) -> String {
        String(format: String(localized: "subscription.yourPlan", bundle: bundle), name)
    }

    // MARK: Premium Features

    static var postcardAddPhoto: String { String(localized: "postcard.addPhoto", bundle: bundle) }
    static var postcardPhotoPremium: String { String(localized: "postcard.photoPremium", bundle: bundle) }
    static var eveningLabel: String { String(localized: "evening.label", bundle: bundle) }
    static var eveningOff: String { String(localized: "evening.off", bundle: bundle) }
    static var eveningCardOk: String { String(localized: "evening.cardOk", bundle: bundle) }
    static var eveningCardNotOk: String { String(localized: "evening.cardNotOk", bundle: bundle) }
    static var eveningPremium: String { String(localized: "evening.premium", bundle: bundle) }
    static var trendsTitle: String { String(localized: "trends.title", bundle: bundle) }
    static var trendsPremium: String { String(localized: "trends.premium", bundle: bundle) }
    static var trendsPremiumHint: String { String(localized: "trends.premiumHint", bundle: bundle) }
    static var trendsEmpty: String { String(localized: "trends.empty", bundle: bundle) }
    static var trendsPeriod: String { String(localized: "trends.period", bundle: bundle) }
    static var exportButton: String { String(localized: "export.button", bundle: bundle) }
    static var exportTitle: String { String(localized: "export.title", bundle: bundle) }
    static var exportMeds: String { String(localized: "export.meds", bundle: bundle) }
    static var exportDays: String { String(localized: "export.days", bundle: bundle) }
    static var exportPremium: String { String(localized: "export.premium", bundle: bundle) }
    static var siblingLocked: String { String(localized: "sibling.locked", bundle: bundle) }
    static var siblingLockedHint: String { String(localized: "sibling.lockedHint", bundle: bundle) }

    static func trendsUsualTime(_ time: String) -> String {
        String(format: String(localized: "trends.usualTime", bundle: bundle), time)
    }

    static func trendsShiftLater(_ minutes: Int) -> String {
        String(format: String(localized: "trends.shiftLater", bundle: bundle), minutes)
    }

    static func trendsShiftEarlier(_ minutes: Int) -> String {
        String(format: String(localized: "trends.shiftEarlier", bundle: bundle), minutes)
    }

    static var trendsShiftNone: String { String(localized: "trends.shiftNone", bundle: bundle) }

    static func trendsMissed(_ count: Int) -> String {
        String(format: String(localized: "trends.missed", bundle: bundle), count)
    }

    static func exportPeriod(_ period: String) -> String {
        String(format: String(localized: "export.period", bundle: bundle), period)
    }

    // MARK: Window, Dates, Stories

    static var windowLabel: String { String(localized: "window.label", bundle: bundle) }
    static var windowPremium: String { String(localized: "window.premium", bundle: bundle) }
    static var datesTitle: String { String(localized: "dates.title", bundle: bundle) }
    static var datesHint: String { String(localized: "dates.hint", bundle: bundle) }
    static var datesPlaceholder: String { String(localized: "dates.placeholder", bundle: bundle) }
    static var datesAdd: String { String(localized: "dates.add", bundle: bundle) }
    static var datesPremium: String { String(localized: "dates.premium", bundle: bundle) }
    static var datesPremiumHint: String { String(localized: "dates.premiumHint", bundle: bundle) }
    static var storiesTitle: String { String(localized: "stories.title", bundle: bundle) }
    static var storiesRowHint: String { String(localized: "stories.rowHint", bundle: bundle) }
    static var storiesEmpty: String { String(localized: "stories.empty", bundle: bundle) }
    static var storiesVoice: String { String(localized: "stories.voice", bundle: bundle) }
    static var storiesPremiumZero: String { String(localized: "stories.premiumZero", bundle: bundle) }
    static var storiesPremiumHint: String { String(localized: "stories.premiumHint", bundle: bundle) }

    static func datesToday(_ title: String) -> String {
        String(format: String(localized: "dates.today", bundle: bundle), title)
    }

    static func datesTomorrow(_ title: String) -> String {
        String(format: String(localized: "dates.tomorrow", bundle: bundle), title)
    }

    static func datesInDays(_ title: String, _ days: Int) -> String {
        String(format: String(localized: "dates.inDays", bundle: bundle), title, days)
    }

    static func storiesPremium(_ count: Int) -> String {
        String(format: String(localized: "stories.premium", bundle: bundle), count)
    }

    // MARK: Placeholders

    static var familyPlaceholder: String { String(localized: "family.placeholder", bundle: bundle) }
}
