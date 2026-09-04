import SwiftUI

// MARK: - Today

struct TodayView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TodayViewModel()
    @State private var postcardTo: Parent?
    @State private var expanded: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model.stage {
                case .loading:
                    loadingCard
                case .failed:
                    failedCard
                case .setup:
                    setupCard
                case .waiting(let code):
                    waitingCard(parent: model.parent, code: code, showsRefresh: true)
                case .ready:
                    if let upcoming = model.upcomingDate {
                        upcomingDateCard(upcoming)
                        Spacer().frame(height: 14)
                    }
                    ForEach(Array(zip(model.cards, model.parents)), id: \.0.id) { card, member in
                        if card.isWaiting {
                            waitingCard(parent: member, code: card.inviteCode, showsRefresh: false)
                            if member.id != model.parents.last?.id {
                                Spacer().frame(height: 26)
                            }
                        } else if isCollapsed(card) {
                            TodayCompactCardView(state: card) {
                                expanded.insert(card.id)
                            }
                            if member.id != model.parents.last?.id {
                                Spacer().frame(height: 12)
                            }
                        } else {
                            TodayStatusCardView(state: card, emphasisesName: hasSeveral) {
                                router.push(.medications(member.id))
                            }
                            Spacer().frame(height: 14)
                            if showsCall(for: card.status) {
                                callButton(for: member)
                                Spacer().frame(height: 12)
                            }
                            postcardButton(for: member)
                            if member.id != model.parents.last?.id {
                                Spacer().frame(height: 26)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .animation(.spring(duration: 0.5), value: model.stage)
        }
        .background(Palette.background)
        .rootToolbar(title: model.dateLine)
        .task(id: model.liveEpoch) {
            await model.load(using: dependencies.checkinService)
            await model.observeUpdates(dependencies.familyUpdates, reloadUsing: dependencies.checkinService)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.load(using: dependencies.checkinService) }
        }
        .sheet(item: $postcardTo) { member in
            PostcardView(parent: member)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Loading / Failed

    private var loadingCard: some View {
        TodayStatusCardView(state: .skeleton, onMedicationsTap: nil)
            .skeleton()
    }

    private var failedCard: some View {
        VStack(spacing: 14) {
            Text(L10n.todayLoadFailed)
                .font(.system(size: 15))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await model.load(using: dependencies.checkinService) }
            } label: {
                Text(L10n.todayRetry)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 22)
        .background(Palette.card, in: .rect(cornerRadius: 24))
        .shadow(color: Palette.ink.opacity(0.05), radius: 16, y: 6)
    }

    // MARK: - Setup Card

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.setupTitle)
                .font(Typography.display(25))
                .foregroundStyle(Palette.ink)

            fieldLabel(L10n.setupYourName)
            TextField(L10n.setupYourNamePlaceholder, text: Bindable(model).childName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.background, in: .rect(cornerRadius: 12))

            Picker("", selection: Bindable(model).childGender) {
                Text(L10n.setupSon).tag("son")
                Text(L10n.setupDaughter).tag("daughter")
            }
            .pickerStyle(.segmented)
            .padding(.top, 10)

            fieldLabel(L10n.setupMomName)
            TextField(L10n.setupMomNamePlaceholder, text: Bindable(model).momName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.background, in: .rect(cornerRadius: 12))

            fieldLabel(L10n.setupCity)
            TextField(L10n.setupCityPlaceholder, text: Bindable(model).cityQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.background, in: .rect(cornerRadius: 12))
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
                        if city != model.citySuggestions.last {
                            Rectangle()
                                .fill(Palette.ink.opacity(0.06))
                                .frame(height: 1)
                        }
                    }
                }
                .background(Palette.background.opacity(0.6), in: .rect(cornerRadius: 12))
                .padding(.top, 4)
            }

            fieldLabel(L10n.setupTime)
            menuRow {
                Picker("", selection: Bindable(model).checkinTime) {
                    ForEach(TodayViewModel.timeOptions, id: \.self) { time in
                        Text(time).tag(time)
                    }
                }
            }

            // The names stay in their own tongue on purpose, same as the
            // app-language switch: mom must recognise hers at a glance.
            fieldLabel(L10n.formBotLanguage)
            menuRow {
                Picker("", selection: Bindable(model).botLang) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
            }

            if model.setupError {
                Text(L10n.setupError)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.alert)
                    .padding(.top, 12)
            }

            Button {
                Task { await model.createFamily() }
            } label: {
                Group {
                    if model.isCreatingFamily {
                        ProgressView().tint(.white)
                    } else {
                        Text(L10n.setupCreate)
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Palette.accent, in: .rect(cornerRadius: 15))
            }
            .disabled(model.isCreatingFamily || model.selectedCity == nil)
            .opacity(model.selectedCity == nil ? 0.55 : 1)
            .padding(.top, 18)

            Rectangle()
                .fill(Palette.accentBright.opacity(0.18))
                .frame(height: 1)
                .padding(.top, 22)

            Text(L10n.restoreTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.top, 16)
            Text(L10n.restoreHint)
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkSecondary)
                .lineSpacing(3)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .background(Palette.card, in: .rect(cornerRadius: 24))
        .shadow(color: Palette.ink.opacity(0.05), radius: 16, y: 6)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.inkSecondary)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func menuRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
                .pickerStyle(.menu)
                .tint(Palette.ink)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Palette.background, in: .rect(cornerRadius: 12))
    }

    // MARK: - Waiting Card

    private func waitingCard(parent: Parent, code: String?, showsRefresh: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(parent.displayName) · \(parent.cityName)")
                .font(Typography.cardTitle)
                .tracking(0.3)
                .foregroundStyle(Palette.inkSecondary)

            Text(L10n.waitingTitle(kind: parent.kind))
                .font(Typography.display(30))
                .foregroundStyle(Palette.ink)
                .padding(.top, 12)

            Text(L10n.waitingText(kind: parent.kind))
                .font(.system(size: 15))
                .foregroundStyle(Palette.inkSecondary)
                .lineSpacing(3)
                .padding(.top, 10)

            if let url = model.inviteURL(code: code) {
                ShareLink(item: url) {
                    Label(L10n.waitingShare(kind: parent.kind), systemImage: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Palette.accent, in: .rect(cornerRadius: 15))
                }
                .padding(.top, 20)
            } else if showsRefresh {
                Button {
                    Task { await model.refreshInvite() }
                } label: {
                    Group {
                        if model.isCreatingFamily {
                            ProgressView().tint(.white)
                        } else {
                            Text(L10n.waitingNewLink)
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.accent, in: .rect(cornerRadius: 15))
                }
                .disabled(model.isCreatingFamily)
                .padding(.top, 20)
            }

            Text(L10n.waitingHint(kind: parent.kind))
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkSecondary.opacity(0.75))
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .background(Palette.card, in: .rect(cornerRadius: 24))
        .shadow(color: Palette.ink.opacity(0.05), radius: 16, y: 6)
    }

    // MARK: - Header

    // MARK: - Upcoming Date

    private func upcomingDateCard(_ upcoming: TodaySnapshot.UpcomingDate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "gift")
                .font(.system(size: 15))
                .foregroundStyle(Palette.accentBright)
            Text(upcomingLine(upcoming))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Palette.card, in: .rect(cornerRadius: 18))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }

    private func upcomingLine(_ upcoming: TodaySnapshot.UpcomingDate) -> String {
        switch upcoming.daysLeft {
        case 0: L10n.datesToday(upcoming.title)
        case 1: L10n.datesTomorrow(upcoming.title)
        default: L10n.datesInDays(upcoming.title, upcoming.daysLeft)
        }
    }

    // MARK: - Postcard

    private func postcardButton(for member: Parent) -> some View {
        Button {
            postcardTo = member
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13))
                Text(hasSeveral ? L10n.postcardButtonFor(member.displayName) : L10n.postcardButton)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Palette.accentBright.opacity(0.10), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var hasSeveral: Bool {
        model.parents.count > 1
    }

    private func isCollapsed(_ card: TodayCardState) -> Bool {
        guard hasSeveral, !expanded.contains(card.id) else { return false }
        switch card.status {
        case .ok, .paused: return true
        default: return false
        }
    }

    private func showsCall(for status: DayStatus) -> Bool {
        switch status {
        case .notOk, .quiet: true
        default: false
        }
    }

    // MARK: - Call

    @Environment(\.openURL) private var openURL

    private func callButton(for member: Parent) -> some View {
        Button {
            if let phone = member.phone, !phone.isEmpty,
               let url = URL(string: "tel://\(phone.filter { !$0.isWhitespace })") {
                openURL(url)
            } else {
                router.push(.parentProfile(member.id))
            }
        } label: {
            Label(L10n.todayCallMom, systemImage: "phone.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Palette.accent, in: .rect(cornerRadius: 16))
        }
    }
}

#Preview {
    NavigationStack { TodayView() }
        .environment(AppRouter())
}
