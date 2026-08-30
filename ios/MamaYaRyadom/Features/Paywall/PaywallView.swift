import SwiftUI
import StoreKit

// MARK: - Paywall

struct PaywallView: View {
    private let model = PurchaseModel.shared
    @State private var selectedID = "ryadom.premium.yearly"
    @State private var isManaging = false

    private static let fallbackPlans: [(id: String, name: String, price: String)] = [
        ("ryadom.premium.monthly", "", "3,99 €"),
        ("ryadom.premium.yearly", "", "29,99 €"),
        ("ryadom.family.yearly", "", "44,99 €"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.paywallBetaBadge)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.okStrong)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.okTint, in: .capsule)

                Text(L10n.paywallTitle)
                    .font(Typography.display(30))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 12)

                Text(L10n.paywallText)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineSpacing(3)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 11) {
                    feature("figure.2", L10n.paywallFeatureParents)
                    feature("pills", L10n.paywallFeatureMeds)
                    feature("calendar", L10n.paywallFeatureHistory)
                    feature("person.3", L10n.paywallFeatureFamily)
                }
                .padding(.top, 18)

                VStack(spacing: 10) {
                    ForEach(plans, id: \.id) { plan in
                        planCard(plan)
                    }
                }
                .padding(.top, 20)

                FormPrimaryButton(
                    title: buyButtonTitle,
                    isEnabled: canBuySelected,
                    isBusy: model.isPurchasing
                ) {
                    Task {
                        if let product = model.products.first(where: { $0.id == selectedID }) {
                            await model.buy(product)
                        }
                    }
                }
                .padding(.top, 20)

                if model.hasSubscription {
                    Button {
                        isManaging = true
                    } label: {
                        Text(L10n.paywallManage)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }

                if model.purchaseState == .pending {
                    Text(L10n.paywallPending)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.warn)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                } else if model.purchaseState == .failed {
                    Text(L10n.paywallFailed)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.alert)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }

                Button {
                    Task { await model.restore() }
                } label: {
                    Text(L10n.paywallRestore)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)

                Text(L10n.paywallDisclaimer)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSecondary.opacity(0.75))
                    .lineSpacing(2)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Palette.background)
        .navigationTitle(L10n.routePaywall)
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $isManaging)
        .task {
            await model.load()
            if let current = model.purchasedIDs.first {
                selectedID = current
            }
        }
    }

    // MARK: - Buy Button

    // Plans live in one subscription group, so buying another product IS the
    // plan switch: the store prorates and retires the old plan itself.
    private var isSelectedPurchased: Bool {
        model.purchasedIDs.contains(selectedID)
    }

    private var buyButtonTitle: String {
        if isSelectedPurchased { return L10n.paywallActive }
        if model.hasSubscription { return L10n.paywallSwitchPlan }
        return L10n.paywallSubscribe
    }

    private var canBuySelected: Bool {
        !isSelectedPurchased && !model.products.isEmpty
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Palette.accentBright)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
                .lineSpacing(2)
        }
    }

    // MARK: - Plans

    private struct Plan {
        let id: String
        let name: String
        let price: String
        let isPurchased: Bool
    }

    private var plans: [Plan] {
        Self.fallbackPlans.map { fallback in
            let product = model.products.first { $0.id == fallback.id }
            return Plan(
                id: fallback.id,
                name: planName(fallback.id, product: product),
                price: product?.displayPrice ?? fallback.price,
                isPurchased: model.purchasedIDs.contains(fallback.id)
            )
        }
    }

    private func planName(_ id: String, product: Product?) -> String {
        if let product, !product.displayName.isEmpty {
            return product.displayName
        }
        switch id {
        case "ryadom.premium.monthly": return L10n.paywallMonthly
        case "ryadom.premium.yearly": return L10n.paywallYearly
        default: return L10n.paywallFamily
        }
    }

    private func planCard(_ plan: Plan) -> some View {
        Button {
            selectedID = plan.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    if plan.isPurchased {
                        Text(L10n.paywallCurrent)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.okStrong)
                    }
                }
                Spacer()
                Text(plan.price)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Palette.card, in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        selectedID == plan.id ? Palette.accent : Palette.ink.opacity(0.08),
                        lineWidth: selectedID == plan.id ? 1.6 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { PaywallView() }
}
