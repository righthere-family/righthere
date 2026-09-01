import Foundation
import Observation
import StoreKit

// MARK: - Purchase State

enum PurchaseState: Equatable {
    case idle
    case pending
    case failed
}

// MARK: - Purchase Model

@Observable
@MainActor
final class PurchaseModel {
    static let shared = PurchaseModel()

    static let productIDs = [
        "righthere.premium.monthly",
        "righthere.premium.yearly",
        "righthere.family.yearly",
    ]

    private(set) var products: [Product] = []
    private(set) var purchasedIDs: Set<String> = []
    private(set) var isPurchasing = false
    private(set) var purchaseState: PurchaseState = .idle

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task {
            for await result in Transaction.unfinished {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await refreshEntitlements()
                }
            }
        }
    }

    private(set) var familyEntitlement: String?
    private(set) var isLoaded = false
    private(set) var trialEligibleIDs: Set<String> = []

    var hasSubscription: Bool {
        !purchasedIDs.isEmpty || familyEntitlement != nil
    }

    func load() async {
        products = ((try? await Product.products(for: Self.productIDs)) ?? [])
            .sorted { $0.price < $1.price }
        await refreshEntitlements()
        if AppConfig.hasFamily {
            familyEntitlement = try? await FamilyAPI().familyEntitlement()
        }
        await refreshTrialEligibility()
        isLoaded = true
    }

    private func refreshTrialEligibility() async {
        var eligible: Set<String> = []
        for product in products {
            guard let subscription = product.subscription,
                  subscription.introductoryOffer?.paymentMode == .freeTrial,
                  await subscription.isEligibleForIntroOffer
            else { continue }
            eligible.insert(product.id)
        }
        trialEligibleIDs = eligible
    }

    func yearlySavings(for productID: String) -> (was: String, percent: Int)? {
        guard let yearly = products.first(where: { $0.id == productID }),
              yearly.subscription?.subscriptionPeriod.unit == .year,
              let monthly = products.first(where: { $0.subscription?.subscriptionPeriod.unit == .month })
        else { return nil }

        let twelveMonths = monthly.price * 12
        guard twelveMonths > yearly.price else { return nil }
        let saved = (twelveMonths - yearly.price) / twelveMonths
        let percent = Int((NSDecimalNumber(decimal: saved).doubleValue * 100).rounded())
        guard percent >= 5 else { return nil }
        return (twelveMonths.formatted(monthly.priceFormatStyle), percent)
    }

    func trialLabel(for productID: String) -> String? {
        guard trialEligibleIDs.contains(productID),
              let offer = products.first(where: { $0.id == productID })?
                  .subscription?.introductoryOffer
        else { return nil }

        var components = DateComponents()
        switch offer.period.unit {
        case .day: components.day = offer.period.value
        case .week: components.weekOfMonth = offer.period.value
        case .month: components.month = offer.period.value
        case .year: components.year = offer.period.value
        @unknown default: components.day = offer.period.value
        }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = L10n.locale
        formatter.calendar = calendar
        guard let period = formatter.string(from: components) else { return nil }
        return L10n.trialFree(period)
    }

    func refreshEntitlements() async {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                ids.insert(transaction.productID)
            }
        }
        purchasedIDs = ids
    }

    func buy(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseState = .idle
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlements()
            case .success(.unverified):
                purchaseState = .failed
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseState = .failed
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
