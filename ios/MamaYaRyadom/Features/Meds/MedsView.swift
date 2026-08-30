import SwiftUI

// MARK: - Meds

struct MedsView: View {
    let parentId: UUID?
    @State private var model = MedsViewModel()
    @State private var isShowingPaywall = false
    @State private var medToRemove: MedInfo?
    @State private var isConfirmingRemoval = false
    private let purchases = PurchaseModel.shared

    private var isAtFreeLimit: Bool {
        model.meds.count >= 1 && model.editingMed == nil && !purchases.hasSubscription
    }

    var body: some View {
        ScrollViewReader { proxy in
            scrollBody(proxy)
        }
    }

    private func scrollBody(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.meds.isEmpty {
                    Text(L10n.medsEmpty)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(Palette.card, in: .rect(cornerRadius: 20))
                } else {
                    ForEach(model.meds) { med in
                        medRow(med, scrollTo: proxy)
                    }
                }
                if isAtFreeLimit {
                    PremiumHintCard(
                        title: L10n.premiumMeds,
                        hint: L10n.premiumMedsHint
                    ) {
                        isShowingPaywall = true
                    }
                } else {
                    addCard
                        .id("editor")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(Palette.background)
        .navigationTitle(L10n.routeMedications)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load(parentId: parentId)
            await purchases.load()
        }
        .sheet(isPresented: $isShowingPaywall) { PaywallSheet() }
        .confirmDialog(
            L10n.confirmRemoveTitle(medToRemove?.title ?? ""),
            actionTitle: L10n.confirmRemoveAction,
            isPresented: $isConfirmingRemoval
        ) {
            guard let med = medToRemove else { return }
            Task { await model.remove(med) }
        }
    }

    // MARK: - Row

    private func medRow(_ med: MedInfo, scrollTo proxy: ScrollViewProxy) -> some View {
        // Tapping anywhere on the row (or the explicit "edit" label) fills the
        // editor card below AND scrolls it into view — filling a form the user
        // cannot see reads as a dead button.
        let beginEdit = {
            model.beginEdit(med)
            // Next runloop: the editor card may only enter the tree with this
            // edit (free tier hides it behind the paywall hint until then).
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("editor", anchor: .bottom)
                }
            }
        }
        return HStack(alignment: .firstTextBaseline) {
            Button(action: beginEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(med.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(med.times.joined(separator: " · "))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button(action: beginEdit) {
                Text(L10n.medsEdit)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
                    .padding(.vertical, 4)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button {
                medToRemove = med
                isConfirmingRemoval = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.inkSecondary.opacity(0.6))
                    .padding(6)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Palette.card, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    model.editingMed?.id == med.id ? Palette.accent.opacity(0.5) : .clear,
                    lineWidth: 1.4
                )
        )
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }

    // MARK: - Add

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.editingMed == nil ? L10n.medsNewTitle : L10n.medsEditTitle)
                    .font(Typography.display(22))
                    .foregroundStyle(Palette.ink)
                Spacer()
                if model.editingMed != nil {
                    Button(L10n.medsCancel) {
                        model.cancelEdit()
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(.plain)
                }
            }

            TextField(L10n.medsNamePlaceholder, text: Bindable(model).newTitle)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.background, in: .rect(cornerRadius: 12))
                .padding(.top, 14)

            ForEach(Bindable(model).slots) { $slot in
                HStack {
                    DatePicker("", selection: $slot.time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer()
                    if model.slots.count > 1 {
                        Button {
                            model.removeSlot(slot)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Palette.inkSecondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }

            if model.slots.count < 4 {
                Button {
                    model.addSlot()
                } label: {
                    Label(L10n.medsAddTime, systemImage: "plus")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }

            Button {
                Task { await model.save() }
            } label: {
                Group {
                    if model.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(model.editingMed == nil ? L10n.medsAdd : L10n.medsSave)
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Palette.accent, in: .rect(cornerRadius: 15))
            }
            .disabled(!model.canSave)
            .opacity(model.canSave ? 1 : 0.55)
            .padding(.top, 16)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Palette.card, in: .rect(cornerRadius: 20))
        .shadow(color: Palette.ink.opacity(0.04), radius: 10, y: 4)
    }
}

#Preview {
    NavigationStack { MedsView(parentId: nil) }
}
