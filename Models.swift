import Foundation

// =====================================================
// BoxVerify - Models.swift（正本・統合）
// ※ SessionManager / Views が参照する型は全てここに集約
// =====================================================

// MARK: - WorkType
enum WorkType: String, Codable, CaseIterable, Identifiable, Hashable {
    case realtime
    case kit
    case scanStats

    // ✅ 互換用（旧コード/Help等が参照する可能性）
    // ※ UI入口に出さないなら WorkSelectionView 側で明示配列にする
    case unlimited

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .realtime: return "checkmark.seal"
        case .kit: return "shippingbox"
        case .scanStats: return "chart.bar"
        case .unlimited: return "infinity"
        }
    }

    var subtitle: String {
        switch self {
        case .realtime: return "完全一致でOK/NG"
        case .kit: return "キット構成品の数量確認"
        case .scanStats: return "コード種別別カウント"
        case .unlimited: return "（互換用）"
        }
    }

    var localizedName: String {
        switch self {
        case .realtime: return "Realtime Verification"
        case .kit: return "Kit Check"
        case .scanStats: return "Scan Stats"
        case .unlimited: return "Unlimited"
        }
    }
}

// MARK: - ProductKind (IAP / Entitlement)
// ✅ All-in は完全撤去（購入対象は realtime / scanStats / kit のみ）
enum ProductKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case realtime      // Realtime
    case scanStats     // Scan Statsプラン
    case kit           // Kitプラン

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .realtime: return "Realtime Unlimitedプラン"
        case .scanStats: return "Scan Stats プラン"
        case .kit: return "Kit プラン"
        }
    }
}

// MARK: - Entitlement State (PurchaseManager SSOT)
enum EntitlementState: String, Codable, Hashable {
    case unknown   // 未確認（初回など）
    case active    // 有効
    case inactive  // 無効（未購入/期限切れ/確認済みで無効）
}

// MARK: - Purchase Verification Result（購入確認の“結果”専用）
struct PurchaseVerificationResult: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case success
        case failure
    }

    let kind: Kind
    let message: String?
    let at: Date

    static func success(_ message: String? = nil, at: Date = Date()) -> PurchaseVerificationResult {
        .init(kind: .success, message: message, at: at)
    }

    static func failure(_ message: String? = nil, at: Date = Date()) -> PurchaseVerificationResult {
        .init(kind: .failure, message: message, at: at)
    }
}

// MARK: - Feature Access
struct FeatureAccess: Codable, Hashable {

    // ✅ associated value があるので自動 Codable は不可 → 手動 Codable 実装で事故防止
    enum Reason: Hashable, Codable {
        case allowed
        case notPurchased
        case unverified
        case offlineGrace(remainingDays: Int)
        case verificationFailed
        case coolingDown

        private enum CodingKeys: String, CodingKey {
            case type
            case remainingDays
        }

        private enum ReasonType: String, Codable {
            case allowed
            case notPurchased
            case unverified
            case offlineGrace
            case verificationFailed
            case coolingDown
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(ReasonType.self, forKey: .type)
            switch type {
            case .allowed:
                self = .allowed
            case .notPurchased:
                self = .notPurchased
            case .unverified:
                self = .unverified
            case .offlineGrace:
                let days = try c.decode(Int.self, forKey: .remainingDays)
                self = .offlineGrace(remainingDays: days)
            case .verificationFailed:
                self = .verificationFailed
            case .coolingDown:
                self = .coolingDown
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .allowed:
                try c.encode(ReasonType.allowed, forKey: .type)
            case .notPurchased:
                try c.encode(ReasonType.notPurchased, forKey: .type)
            case .unverified:
                try c.encode(ReasonType.unverified, forKey: .type)
            case .offlineGrace(let remainingDays):
                try c.encode(ReasonType.offlineGrace, forKey: .type)
                try c.encode(remainingDays, forKey: .remainingDays)
            case .verificationFailed:
                try c.encode(ReasonType.verificationFailed, forKey: .type)
            case .coolingDown:
                try c.encode(ReasonType.coolingDown, forKey: .type)
            }
        }
    }

    let isAllowed: Bool
    let reason: Reason

    static let allowed: FeatureAccess = .init(isAllowed: true, reason: .allowed)
}

// MARK: - Verification Outcome Kind（Realtime等の“判定結果”用）
enum VerificationOutcomeKind: String, Codable, Hashable {
    case ok
    case ng
    case notJudged
}

// MARK: - Help Category（HelpView が参照するカテゴリ）
enum HelpCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case unlimited
    case purchase
    case scanStats
    case kit
    case troubleshooting

    var id: String { rawValue }
}

// MARK: - EntitlementSnapshot（正本）
struct EntitlementSnapshot: Codable, Equatable, Hashable {
    let activeProducts: Set<ProductKind>
}

// MARK: - PurchaseDiagnosticsSnapshot（正本）
struct PurchaseDiagnosticsSnapshot: Codable, Equatable, Hashable {
    let entitlementState: EntitlementState
    let lastVerifiedAt: Date?
    let lastKnownEntitlement: EntitlementSnapshot?
    let remainingDays: Int
    let lastVerificationResult: PurchaseVerificationResult?
    let autoVerifyEnabled: Bool
}

// =====================================================
// Session / Suspended / Kit / ScanStats（SessionManagerが参照）
// =====================================================

// MARK: - CapturedEntitlement（作業開始時に固定するスナップショット）
struct CapturedEntitlement: Codable, Hashable {
    let activeProducts: Set<ProductKind>
    let capturedAt: Date

    init(activeProducts: Set<ProductKind>, capturedAt: Date = Date()) {
        self.activeProducts = activeProducts
        self.capturedAt = capturedAt
    }

    init(from snapshot: EntitlementSnapshot, capturedAt: Date = Date()) {
        self.activeProducts = snapshot.activeProducts
        self.capturedAt = capturedAt
    }

    // ✅ View側の呼び出しに合わせた initializer（正本）
    init(
        unlimitedState: EntitlementState,
        scanStatsState: EntitlementState,
        kitState: EntitlementState,
        capturedAt: Date = Date()
    ) {
        var products = Set<ProductKind>()
        if unlimitedState == .active { products.insert(.realtime) }
        if scanStatsState == .active { products.insert(.scanStats) }
        if kitState == .active { products.insert(.kit) }
        self.activeProducts = products
        self.capturedAt = capturedAt
    }

    var unlimitedState: EntitlementState {
        activeProducts.contains(.realtime) ? .active : .inactive
    }

    var scanStatsState: EntitlementState {
        activeProducts.contains(.scanStats) ? .active : .inactive
    }

    var kitState: EntitlementState {
        activeProducts.contains(.kit) ? .active : .inactive
    }
}

// MARK: - RealtimeSession（✅ verificationScans を追加して永続化）
struct RealtimeSession: Codable, Hashable {
    let entitlementAtStart: CapturedEntitlement

    // ✅ 追加：照合スキャン回数（Base Code登録は含めない）
    var verificationScans: Int

    var lastScannedCode: String?
    var lastOutcome: VerificationOutcomeKind?
    let startedAt: Date

    init(
        entitlementAtStart: CapturedEntitlement,
        verificationScans: Int = 0,
        lastScannedCode: String? = nil,
        lastOutcome: VerificationOutcomeKind? = nil,
        startedAt: Date = Date()
    ) {
        self.entitlementAtStart = entitlementAtStart
        self.verificationScans = verificationScans
        self.lastScannedCode = lastScannedCode
        self.lastOutcome = lastOutcome
        self.startedAt = startedAt
    }
}

// MARK: - KitDefinition / KitStore（正本）
struct KitDefinition: Codable, Hashable, Identifiable {
    let id: UUID
    let kitId: String
    let requiredCounts: [String: Int]

    init(id: UUID = UUID(), kitId: String, requiredCounts: [String: Int]) {
        self.id = id
        self.kitId = kitId
        self.requiredCounts = requiredCounts
    }
}

struct KitStore: Codable, Hashable {
    var definitions: [String: KitDefinition] = [:]

    func definition(for kitId: String) -> KitDefinition? {
        definitions[kitId]
    }
}

// MARK: - KitSession
struct KitSession: Codable, Hashable {
    let entitlementAtStart: CapturedEntitlement
    var kitId: String?
    var requiredCounts: [String: Int]
    var scannedCounts: [String: Int]
    let startedAt: Date
    var lastUpdatedAt: Date

    init(
        entitlementAtStart: CapturedEntitlement,
        kitId: String? = nil,
        requiredCounts: [String: Int] = [:],
        scannedCounts: [String: Int] = [:],
        startedAt: Date = Date(),
        lastUpdatedAt: Date = Date()
    ) {
        self.entitlementAtStart = entitlementAtStart
        self.kitId = kitId
        self.requiredCounts = requiredCounts
        self.scannedCounts = scannedCounts
        self.startedAt = startedAt
        self.lastUpdatedAt = lastUpdatedAt
    }

    var isKitSelected: Bool { kitId != nil }
    var isEmptyRequired: Bool { requiredCounts.isEmpty }

    var progressSummary: (scanned: Int, required: Int) {
        let scannedTotal = scannedCounts.values.reduce(0, +)
        let requiredTotal = requiredCounts.values.reduce(0, +)
        return (scannedTotal, requiredTotal)
    }

    var isCompleted: Bool {
        guard !requiredCounts.isEmpty else { return false }
        for (code, req) in requiredCounts {
            let got = scannedCounts[code, default: 0]
            if got < req { return false }
        }
        return true
    }
}

// MARK: - KitScanOutcome（SessionManager.scanKitComponent の戻り値）
enum KitScanOutcome: Hashable {
    case progress
    case completedOK
    case completedNG(reason: String)
    case noSession
}

// MARK: - ScanStatsSession
struct ScanStatsSession: Codable, Hashable {
    let entitlementAtStart: CapturedEntitlement
    var totalScans: Int
    var codeCounts: [String: Int]
    let startedAt: Date
    var lastUpdatedAt: Date

    init(
        entitlementAtStart: CapturedEntitlement,
        totalScans: Int = 0,
        codeCounts: [String: Int] = [:],
        startedAt: Date = Date(),
        lastUpdatedAt: Date = Date()
    ) {
        self.entitlementAtStart = entitlementAtStart
        self.totalScans = totalScans
        self.codeCounts = codeCounts
        self.startedAt = startedAt
        self.lastUpdatedAt = lastUpdatedAt
    }

    var typesCount: Int { codeCounts.keys.count }
}

// MARK: - ScanStatsCountResult（SessionManager.scanStatsCount の戻り値）
enum ScanStatsCountResult: Hashable {
    case success
    case maxTypesReached
    case maxTotalReached
    case noSession
}

// MARK: - SuspendedPayload（associated value / Codable）
enum SuspendedPayload: Codable, Hashable {
    case realtime(RealtimeSession)
    case kit(KitSession)
    case scanStats(ScanStatsSession)

    private enum CodingKeys: String, CodingKey {
        case type, realtime, kit, scanStats
    }

    private enum PayloadType: String, Codable {
        case realtime, kit, scanStats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)
        switch type {
        case .realtime:
            self = .realtime(try container.decode(RealtimeSession.self, forKey: .realtime))
        case .kit:
            self = .kit(try container.decode(KitSession.self, forKey: .kit))
        case .scanStats:
            self = .scanStats(try container.decode(ScanStatsSession.self, forKey: .scanStats))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .realtime(let value):
            try container.encode(PayloadType.realtime, forKey: .type)
            try container.encode(value, forKey: .realtime)
        case .kit(let value):
            try container.encode(PayloadType.kit, forKey: .type)
            try container.encode(value, forKey: .kit)
        case .scanStats(let value):
            try container.encode(PayloadType.scanStats, forKey: .type)
            try container.encode(value, forKey: .scanStats)
        }
    }
}

// MARK: - SuspendedSession（最大1件 / 7日で期限切れ）
struct SuspendedSession: Codable, Hashable, Identifiable {
    let id: UUID
    let savedAt: Date
    let payload: SuspendedPayload

    init(id: UUID = UUID(), savedAt: Date = Date(), payload: SuspendedPayload) {
        self.id = id
        self.savedAt = savedAt
        self.payload = payload
    }

    static let retentionDays: Int = 7

    var remainingDays: Int {
        let cal = Calendar.current
        let expireAt = cal.date(byAdding: .day, value: Self.retentionDays, to: savedAt) ?? savedAt
        let diff = cal.dateComponents([.day], from: Date(), to: expireAt).day ?? 0
        return max(0, diff)
    }

    var isExpired: Bool { remainingDays <= 0 }
}
