import Foundation
import Combine
import StoreKit

@MainActor
final class HoldOnPurchaseManager: ObservableObject {
    static let shared = HoldOnPurchaseManager()
    static let fullAccessProductID = "com.soso.holdon.fullaccess"
    static let initialFreeTrialUses = 5
    private static let freeTrialUsedCountKey = "holdon.premium.freeTrial.used.v1"

    @Published private(set) var fullAccessProduct: Product?
    @Published private(set) var hasFullAccess = false
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isPurchasing = false
    @Published var message: String?
    @Published private(set) var freeTrialRemainingUses: Int

    private var updatesTask: Task<Void, Never>?

    private init() {
        let used = max(0, UserDefaults.standard.integer(forKey: Self.freeTrialUsedCountKey))
        freeTrialRemainingUses = max(0, Self.initialFreeTrialUses - used)
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }

        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }


    /// Uses one of the five launch trial passes for a premium action.
    /// Returns the remaining trial count after consumption, or nil when no free pass remains.
    @discardableResult
    func consumeFreeTrialUseIfAvailable() -> Int? {
        guard !hasFullAccess, freeTrialRemainingUses > 0 else { return nil }
        let nextRemaining = freeTrialRemainingUses - 1
        freeTrialRemainingUses = nextRemaining
        let used = Self.initialFreeTrialUses - nextRemaining
        UserDefaults.standard.set(used, forKey: Self.freeTrialUsedCountKey)
        return nextRemaining
    }

    func loadProduct() async {
        guard fullAccessProduct == nil, !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            fullAccessProduct = try await Product.products(for: [Self.fullAccessProductID]).first
        } catch {
            message = "구매 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.fullAccessProductID,
               transaction.revocationDate == nil {
                entitled = true
                break
            }
        }
        hasFullAccess = entitled
    }

    @discardableResult
    func purchaseFullAccess() async -> Bool {
        if hasFullAccess { return true }
        if fullAccessProduct == nil { await loadProduct() }
        guard let product = fullAccessProduct else {
            message = "Full Access 상품 정보를 아직 불러오지 못했어요."
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = "구매 확인에 실패했어요."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return hasFullAccess
            case .pending:
                message = "구매 승인을 기다리고 있어요."
                return false
            case .userCancelled:
                return false
            @unknown default:
                message = "구매를 완료하지 못했어요."
                return false
            }
        } catch {
            message = "구매 중 문제가 생겼어요.\n\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !hasFullAccess {
                message = "복원할 Full Access 구매 내역을 찾지 못했어요."
            }
            return hasFullAccess
        } catch {
            message = "구매 복원에 실패했어요.\n\(error.localizedDescription)"
            return false
        }
    }
}
