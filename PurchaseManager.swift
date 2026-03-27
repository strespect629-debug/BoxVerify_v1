import Foundation
import Combine
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    private init() {
        loadPersisted()

        // 最新IDで強制上書き
        productIDsByKindCache = defaultProductIDsByKind
        persist()

        recomputeOfflineGrace()
        startTransactionListener()
    }

    // MARK: - SSOT

    @Published private(set) var entitlementState: EntitlementState = .unknown
    @Published private(set) var lastVerifiedAt: Date? = nil
    @Published private(set) var lastKnownEntitlement: EntitlementSnapshot? = nil
    @Published private(set) var remainingDays: Int = 0
    @Published private(set) var lastVerificationResult: PurchaseVerificationResult? = nil

    // MARK: - Products

    @Published private(set) var productsByKind: [ProductKind: Product] = [:]
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var isPurchasing: Bool = false

    @Published var autoVerifyEnabled: Bool = false {
        didSet { persist() }
    }

    // MARK: - Debug / Diagnostics

    @Published private(set) var lastEntitlementProductIDs: [String] = []
    @Published private(set) var lastSubscriptionStatesByID: [String: String] = [:]
    @Published private(set) var lastActiveKindsDebug: [String] = []

    // MARK: - Product IDs

    private let defaultProductIDsByKind: [ProductKind: String] = [
        .realtime: "com.boxverify.app.realtime.sub",
        .scanStats: "com.boxverify.app.scanstats.sub",
        .kit: "com.boxverify.app.kit"
    ]

    private var productIDsByKindCache: [ProductKind: String] = [:]

    private let offlineGraceDays: Int = 7

    // MARK: - Access

    var realtimeAccess: FeatureAccess { featureAccess(for: .realtime) }
    var scanStatsAccess: FeatureAccess { featureAccess(for: .scanStats) }
    var kitAccess: FeatureAccess { featureAccess(for: .kit) }

    private func featureAccess(for kind: ProductKind) -> FeatureAccess {
        let snapshot = lastKnownEntitlement
        let hasActive = snapshot?.activeProducts.contains(kind) == true

        if entitlementState == .active {
            return hasActive
                ? FeatureAccess(isAllowed: true, reason: .allowed)
                : FeatureAccess(isAllowed: false, reason: .notPurchased)
        }

        if entitlementState == .unknown,
           hasActive,
           remainingDays > 0,
           lastVerifiedAt != nil {
            return FeatureAccess(
                isAllowed: true,
                reason: .offlineGrace(remainingDays: remainingDays)
            )
        }

        if let result = lastVerificationResult,
           result.kind == .failure {
            return FeatureAccess(isAllowed: false, reason: .verificationFailed)
        }

        switch entitlementState {
        case .inactive:
            return FeatureAccess(isAllowed: false, reason: .notPurchased)

        case .unknown:
            return FeatureAccess(isAllowed: false, reason: .unverified)

        case .active:
            return hasActive
                ? FeatureAccess(isAllowed: true, reason: .allowed)
                : FeatureAccess(isAllowed: false, reason: .notPurchased)

        @unknown default:
            return FeatureAccess(isAllowed: false, reason: .unverified)
        }
    }

    // MARK: - Auto Verify

    func autoVerifyIfEnabled() async {
        recomputeOfflineGrace()
        persist()
    }

    // MARK: - Purchase

    func purchase(kind: ProductKind, productIDsByKind: [ProductKind: String]) async {
        let map = effectiveProductIDsByKind(productIDsByKind)
        updateProductIDsCache(map)

        if isPurchasing { return }

        isPurchasing = true
        defer { isPurchasing = false }

        if productsByKind[kind] == nil {
            await loadProducts(productIDsByKind: map)
        }

        guard let product = productsByKind[kind] else {
            let productID = map[kind] ?? "(unknown)"
            lastVerificationResult = .failure("商品取得失敗: \(productID)", at: Date())
            persist()
            return
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()

                case .unverified(_, let error):
                    lastVerificationResult = .failure(
                        "購入検証に失敗しました: \(error.localizedDescription)",
                        at: Date()
                    )
                    persist()
                }

            case .pending:
                lastVerificationResult = .success("購入保留中", at: Date())
                persist()

            case .userCancelled:
                lastVerificationResult = .success("キャンセル", at: Date())
                persist()

            @unknown default:
                lastVerificationResult = .failure("不明な結果", at: Date())
                persist()
            }

        } catch {
            lastVerificationResult = .failure(error.localizedDescription, at: Date())
            persist()
        }
    }

    // MARK: - Entitlement

    func refreshEntitlements() async {
        let map = effectiveProductIDsByKind(productIDsByKindCache)
        updateProductIDsCache(map)

        var active: Set<ProductKind> = []
        var entitlementIDs: [String] = []
        var subscriptionStates: [String: String] = [:]

        let ids = Array(map.values)

        do {
            let fetchedProducts = try await Product.products(for: ids)

            var newProductsByKind: [ProductKind: Product] = [:]
            var productsByID: [String: Product] = [:]

            for product in fetchedProducts {
                productsByID[product.id] = product
            }

            for (kind, id) in map {
                if let product = productsByID[id] {
                    newProductsByKind[kind] = product
                }
            }

            productsByKind = newProductsByKind

            let idToKind = makeProductIDReverseMap()

            // ① 最優先: Transaction.currentEntitlements
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }

                entitlementIDs.append(transaction.productID)

                if let kind = idToKind[transaction.productID] {
                    active.insert(kind)
                }
            }

            // ② 補助: subscription.status
            for (kind, id) in map {
                guard let product = productsByID[id] else {
                    subscriptionStates[id] = "productNotLoaded"
                    continue
                }

                guard let subscription = product.subscription else {
                    subscriptionStates[id] = "noSubscriptionObject"
                    continue
                }

                do {
                    let statuses = try await subscription.status
                    let label = subscriptionStatusLabel(statuses)
                    subscriptionStates[id] = label

                    if isSubscriptionActive(statuses) {
                        active.insert(kind)
                    }
                } catch {
                    subscriptionStates[id] = "statusError: \(error.localizedDescription)"
                }
            }

        } catch {
            lastEntitlementProductIDs = []
            lastSubscriptionStatesByID = Dictionary(
                uniqueKeysWithValues: ids.map { ($0, "productFetchError: \(error.localizedDescription)") }
            )
            lastActiveKindsDebug = []

            lastVerificationResult = .failure(
                "購入情報更新失敗: \(error.localizedDescription)",
                at: Date()
            )
            persist()
            return
        }

        entitlementIDs.sort()
        let activeKindsDebug = active.map(\.rawValue).sorted()

        lastEntitlementProductIDs = entitlementIDs
        lastSubscriptionStatesByID = subscriptionStates
        lastActiveKindsDebug = activeKindsDebug

        lastKnownEntitlement = EntitlementSnapshot(activeProducts: active)
        lastVerifiedAt = Date()
        entitlementState = active.isEmpty ? .inactive : .active
        lastVerificationResult = .success("購入情報更新完了", at: Date())

        recomputeOfflineGrace()
        persist()
    }

    // MARK: - Restore

    func restorePurchasesByUserAction() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastVerificationResult = .success("購入を復元しました", at: Date())
        } catch {
            lastVerificationResult = .failure("復元失敗: \(error.localizedDescription)", at: Date())
        }

        persist()
    }

    // MARK: - Products

    func loadProductsIfNeeded(productIDsByKind: [ProductKind: String]) async {
        let map = effectiveProductIDsByKind(productIDsByKind)
        updateProductIDsCache(map)

        let hasAllKinds = map.keys.allSatisfy { productsByKind[$0] != nil }
        if hasAllKinds { return }

        await loadProducts(productIDsByKind: map)
    }

    func loadProducts(productIDsByKind: [ProductKind: String]) async {
        let map = effectiveProductIDsByKind(productIDsByKind)
        updateProductIDsCache(map)

        if isLoadingProducts { return }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetchedProducts = try await Product.products(for: Array(map.values))

            var newMap: [ProductKind: Product] = [:]

            for (kind, id) in map {
                if let product = fetchedProducts.first(where: { $0.id == id }) {
                    newMap[kind] = product
                }
            }

            productsByKind = newMap

            let missingKinds = map.keys
                .filter { newMap[$0] == nil }
                .sorted { $0.rawValue < $1.rawValue }

            if missingKinds.isEmpty {
                lastVerificationResult = .success("価格情報を取得しました。", at: Date())
            } else {
                let missingIDs = missingKinds.compactMap { map[$0] }
                lastVerificationResult = .failure(
                    "価格情報を取得できない商品があります: \(missingIDs.joined(separator: ", "))",
                    at: Date()
                )
            }

        } catch {
            lastVerificationResult = .failure("価格取得失敗: \(error.localizedDescription)", at: Date())
        }

        persist()
    }

    // MARK: - Diagnostics Helpers

    func loadedProductKinds() -> [ProductKind] {
        productsByKind.keys.sorted { $0.rawValue < $1.rawValue }
    }

    func loadedProductIDs() -> [String] {
        productsByKind.values.map(\.id).sorted()
    }

    func cachedProductIDsByKind() -> [ProductKind: String] {
        productIDsByKindCache
    }

    func lastEntitlementProductIDsDebug() -> [String] {
        lastEntitlementProductIDs
    }

    func lastSubscriptionStatesByIDDebug() -> [String: String] {
        lastSubscriptionStatesByID
    }

    func lastActiveKindsDebugValues() -> [String] {
        lastActiveKindsDebug
    }

    // MARK: - Helpers

    private func isSubscriptionActive(_ statuses: [Product.SubscriptionInfo.Status]) -> Bool {
        statuses.contains {
            $0.state == .subscribed ||
            $0.state == .inGracePeriod ||
            $0.state == .inBillingRetryPeriod
        }
    }

    private func subscriptionStatusLabel(_ statuses: [Product.SubscriptionInfo.Status]) -> String {
        if statuses.isEmpty { return "empty" }

        let labels = statuses.map { status -> String in
            let stateText: String
            switch status.state {
            case .subscribed:
                stateText = "subscribed"
            case .inGracePeriod:
                stateText = "inGracePeriod"
            case .inBillingRetryPeriod:
                stateText = "inBillingRetryPeriod"
            case .expired:
                stateText = "expired"
            case .revoked:
                stateText = "revoked"
            default:
                stateText = "unknown"
            }

            return stateText
        }

        return labels.joined(separator: ",")
    }

    private func effectiveProductIDsByKind(_ input: [ProductKind: String]) -> [ProductKind: String] {
        if !input.isEmpty { return input }
        if !productIDsByKindCache.isEmpty { return productIDsByKindCache }
        return defaultProductIDsByKind
    }

    private func updateProductIDsCache(_ map: [ProductKind: String]) {
        guard !map.isEmpty else { return }
        productIDsByKindCache = map
        persist()
    }

    private func makeProductIDReverseMap() -> [String: ProductKind] {
        Dictionary(
            uniqueKeysWithValues: productIDsByKindCache.map { ($0.value, $0.key) }
        )
    }

    private func recomputeOfflineGrace() {
        guard let last = lastVerifiedAt else {
            remainingDays = 0
            return
        }

        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        remainingDays = max(0, offlineGraceDays - days)
    }

    // MARK: - Listener

    private var listenerTask: Task<Void, Never>?

    private func startTransactionListener() {
        if listenerTask != nil { return }

        listenerTask = Task { [weak self] in
            guard let self else { return }

            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    // MARK: - Persist

    private struct PersistedState: Codable {
        let entitlementState: EntitlementState
        let lastVerifiedAt: Date?
        let lastKnownEntitlement: EntitlementSnapshot?
        let lastVerificationResult: PurchaseVerificationResult?
        let autoVerifyEnabled: Bool
        let productIDsByKindRaw: [String: String]
    }

    private func persist() {
        let raw = Dictionary(
            uniqueKeysWithValues: productIDsByKindCache.map { ($0.key.rawValue, $0.value) }
        )

        let state = PersistedState(
            entitlementState: entitlementState,
            lastVerifiedAt: lastVerifiedAt,
            lastKnownEntitlement: lastKnownEntitlement,
            lastVerificationResult: lastVerificationResult,
            autoVerifyEnabled: autoVerifyEnabled,
            productIDsByKindRaw: raw
        )

        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "PurchaseManager.State")
        }
    }

    private func loadPersisted() {
        guard
            let data = UserDefaults.standard.data(forKey: "PurchaseManager.State"),
            let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return }

        entitlementState = state.entitlementState
        lastVerifiedAt = state.lastVerifiedAt
        lastKnownEntitlement = state.lastKnownEntitlement
        lastVerificationResult = state.lastVerificationResult
        autoVerifyEnabled = state.autoVerifyEnabled

        productIDsByKindCache = Dictionary(
            uniqueKeysWithValues: state.productIDsByKindRaw.compactMap {
                guard let kind = ProductKind(rawValue: $0.key) else { return nil }
                return (kind, $0.value)
            }
        )
    }

    // MARK: - Diagnostics

    func diagnosticsSnapshot() -> PurchaseDiagnosticsSnapshot {
        PurchaseDiagnosticsSnapshot(
            entitlementState: entitlementState,
            lastVerifiedAt: lastVerifiedAt,
            lastKnownEntitlement: lastKnownEntitlement,
            remainingDays: remainingDays,
            lastVerificationResult: lastVerificationResult,
            autoVerifyEnabled: autoVerifyEnabled
        )
    }
}
