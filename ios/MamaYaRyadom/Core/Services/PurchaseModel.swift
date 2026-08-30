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
        "ryadom.premium.monthly",
        "ryadom.premium.yearly",
        "ryadom.family.yearly",
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

    var hasSubscription: Bool {
        !purchasedIDs.isEmpty
    }

    func load() async {
        products = ((try? await Product.products(for: Self.productIDs)) ?? [])
            .sorted { $0.price < $1.price }
        await refreshEntitlements()
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
