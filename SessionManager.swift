import Foundation
import Combine

// ============================================================
// MARK: - SessionManager (SSOT)
// - 集計・状態の正はここ。Viewは保持しない。
// - 権利判断は PurchaseManager、表示ロックは View 側で行う。
// ============================================================

@MainActor
final class SessionManager: ObservableObject {

    static let shared = SessionManager()

    private init() {
        loadPersistedAll()
        purgeExpiredSuspendedIfNeeded()
    }

    // ============================================================
    // MARK: - Published SSOT
    // ============================================================

    @Published private(set) var baseCode: String? = nil
    @Published private(set) var kitStore: KitStore = KitStore()

    @Published private(set) var currentRealtimeSession: RealtimeSession? = nil
    @Published private(set) var currentKitSession: KitSession? = nil
    @Published private(set) var currentScanStatsSession: ScanStatsSession? = nil

    /// 中断は最大1件
    @Published private(set) var suspendedSession: SuspendedSession? = nil

    // ============================================================
    // MARK: - Limits (fixed)
    // ============================================================

    // ✅ 正本：Scan Stats 上限（1セッション）
    // - 種類数：10種類
    // - トータル：1,000回
    // ※ 判定は >= でブロック（11種類目 / 1001回目が入る事故を根絶）
    private let scanStatsMaxTypes: Int = 10
    private let scanStatsMaxTotal: Int = 1_000

    private let maxKitsAllowedDefault: Int = 5
    private let maxItemsPerKit: Int = 5

    // ============================================================
    // MARK: - Diagnostics helper
    // ============================================================

    func kitDefinitionsCount() -> Int {
        kitStore.definitions.count
    }

    // ============================================================
    // MARK: - Base Code
    // ============================================================

    /// Base Code を設定（trim適用・空はnil）
    /// - 改行/制御文字を含む場合は登録拒否（事故防止）
    @discardableResult
    func setBaseCode(_ newValue: String?) -> Bool {
        guard let raw = newValue else {
            baseCode = nil
            persistAll()
            return true
        }

        // ✅ 正本：trim前の生文字列で制御文字を検査
        if containsForbiddenControlChars(raw) {
            return false
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            baseCode = nil
            persistAll()
            return true
        }

        baseCode = trimmed
        persistAll()
        return true
    }

    // ============================================================
    // MARK: - Kit Store（SSOT）
    // ============================================================

    func upsertKit(
        kitId: String,
        requiredCounts: [String: Int],
        maxKitsAllowedOverride: Int? = nil
    ) {
        let trimmedKitId = kitId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKitId.isEmpty else { return }
        if containsForbiddenControlChars(trimmedKitId) { return }

        let maxKitsAllowed = max(1, maxKitsAllowedOverride ?? maxKitsAllowedDefault)

        var sanitized: [String: Int] = [:]
        for (codeRaw, qtyRaw) in requiredCounts {
            let code = codeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }
            if containsForbiddenControlChars(code) { continue }
            sanitized[code] = max(1, qtyRaw)
        }

        if sanitized.count > maxItemsPerKit {
            let keys = sanitized.keys.sorted()
            let allowed = Set(keys.prefix(maxItemsPerKit))
            sanitized = sanitized.filter { allowed.contains($0.key) }
        }

        guard !sanitized.isEmpty else { return }

        var newDefs = kitStore.definitions

        // ✅ 同一KitIDの大文字小文字違いは同一扱い
        let existingMatchedKey = newDefs.keys.first {
            $0.lowercased() == trimmedKitId.lowercased()
        }

        if existingMatchedKey == nil && newDefs.count >= maxKitsAllowed {
            return
        }

        let storageKey = existingMatchedKey ?? trimmedKitId
        let idToUse = newDefs[storageKey]?.id ?? UUID()

        newDefs[storageKey] = KitDefinition(
            id: idToUse,
            kitId: trimmedKitId,
            requiredCounts: sanitized
        )

        kitStore = KitStore(definitions: newDefs)
        persistAll()
    }

    func deleteKit(kitId: String) {
        let trimmedKitId = kitId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKitId.isEmpty else { return }

        var newDefs = kitStore.definitions

        if let exact = newDefs[trimmedKitId] {
            newDefs.removeValue(forKey: exact.kitId)
        } else if let matchedKey = newDefs.keys.first(where: { $0.lowercased() == trimmedKitId.lowercased() }) {
            newDefs.removeValue(forKey: matchedKey)
        } else {
            return
        }

        kitStore = KitStore(definitions: newDefs)
        persistAll()
    }

    private func kitDefinitionCaseInsensitive(for kitId: String) -> KitDefinition? {
        let trimmed = kitId.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = trimmed.lowercased()
        if target.isEmpty { return nil }

        if let exact = kitStore.definitions[trimmed] {
            return exact
        }

        for (storedKey, def) in kitStore.definitions {
            if storedKey.lowercased() == target {
                return def
            }
            if def.kitId.lowercased() == target {
                return def
            }
        }

        return nil
    }

    // ============================================================
    // MARK: - Realtime Session
    // - verificationScans は「照合してOK/NGを確定した時だけ」+1
    // - Base Code 登録/未判定/トライアル上限破棄では増やさない
    // ============================================================

    func startRealtimeSessionIfNeeded(entitlementAtStart: CapturedEntitlement) {
        if currentRealtimeSession != nil { return }
        currentRealtimeSession = RealtimeSession(
            entitlementAtStart: entitlementAtStart,
            verificationScans: 0,
            lastScannedCode: nil,
            lastOutcome: nil,
            startedAt: Date()
        )
        persistAll()
    }

    /// 互換：最後のスキャン情報だけ更新（回数は増やさない）
    func updateRealtimeLastScan(code: String, outcome: VerificationOutcomeKind) {
        guard var s = currentRealtimeSession else { return }
        s.lastScannedCode = code
        s.lastOutcome = outcome
        currentRealtimeSession = s
        persistAll()
    }

    /// 正本：照合を実行した時だけ呼ぶ（ここでのみ回数 +1）
    func recordRealtimeVerification(code: String, outcome: VerificationOutcomeKind) {
        guard var s = currentRealtimeSession else { return }
        s.verificationScans += 1
        s.lastScannedCode = code
        s.lastOutcome = outcome
        currentRealtimeSession = s
        persistAll()
    }

    // ============================================================
    // MARK: - Kit Session
    // ============================================================

    func startKitSessionIfNeeded(entitlementAtStart: CapturedEntitlement) {
        if currentKitSession != nil { return }
        currentKitSession = KitSession(
            entitlementAtStart: entitlementAtStart,
            kitId: nil,
            requiredCounts: [:],
            scannedCounts: [:],
            startedAt: Date(),
            lastUpdatedAt: Date()
        )
        persistAll()
    }

    func selectKitId(_ kitId: String) {
        guard var s = currentKitSession else { return }

        let trimmed = kitId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if containsForbiddenControlChars(trimmed) { return }

        let def = kitDefinitionCaseInsensitive(for: trimmed)

        // ✅ 定義が見つかった場合は定義側の正規化済み kitId を採用
        s.kitId = def?.kitId ?? trimmed
        s.requiredCounts = def?.requiredCounts ?? [:]
        s.scannedCounts = [:]
        s.lastUpdatedAt = Date()

        currentKitSession = s
        persistAll()
    }

    func scanKitComponent(_ code: String) -> KitScanOutcome {
        guard var s = currentKitSession else { return .noSession }
        guard s.kitId != nil else { return .noSession }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .progress }
        if containsForbiddenControlChars(trimmed) {
            return .completedNG(reason: "無効な文字（改行/制御文字）が含まれています")
        }

        if s.requiredCounts.isEmpty {
            return .completedNG(reason: "構成品が登録されていません")
        }

        guard let required = s.requiredCounts[trimmed] else {
            return .completedNG(reason: "キットに含まれないコードです")
        }

        let current = s.scannedCounts[trimmed] ?? 0
        if current + 1 > required {
            return .completedNG(reason: "必要数を超えてスキャンされています")
        }

        s.scannedCounts[trimmed] = current + 1
        s.lastUpdatedAt = Date()
        currentKitSession = s
        persistAll()

        if isKitCompleted(s) {
            return .completedOK
        }
        return .progress
    }

    private func isKitCompleted(_ s: KitSession) -> Bool {
        guard !s.requiredCounts.isEmpty else { return false }
        for (code, required) in s.requiredCounts {
            let scanned = s.scannedCounts[code] ?? 0
            if scanned < required { return false }
        }
        return true
    }

    // ============================================================
    // MARK: - Scan Stats Session (集計SSOT)
    // ============================================================

    func startScanStatsSessionIfNeeded(entitlementAtStart: CapturedEntitlement) {
        if currentScanStatsSession != nil { return }
        currentScanStatsSession = ScanStatsSession(
            entitlementAtStart: entitlementAtStart,
            totalScans: 0,
            codeCounts: [:],
            startedAt: Date(),
            lastUpdatedAt: Date()
        )
        persistAll()
    }

    /// 正本：引数ラベル無し
    func scanStatsCount(_ code: String) -> ScanStatsCountResult {
        guard var s = currentScanStatsSession else { return .noSession }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success }
        if containsForbiddenControlChars(trimmed) { return .success }

        // ✅ 1000回上限（>=でブロック）
        if s.totalScans >= scanStatsMaxTotal {
            return .maxTotalReached
        }

        // ✅ 10種類上限（新種追加時のみ >=でブロック）
        let isNewType = (s.codeCounts[trimmed] == nil)
        if isNewType && s.codeCounts.count >= scanStatsMaxTypes {
            return .maxTypesReached
        }

        s.totalScans += 1
        s.codeCounts[trimmed, default: 0] += 1
        s.lastUpdatedAt = Date()

        currentScanStatsSession = s
        persistAll()
        return .success
    }

    func resetScanStats(entitlementAtStart: CapturedEntitlement) {
        currentScanStatsSession = ScanStatsSession(
            entitlementAtStart: entitlementAtStart,
            totalScans: 0,
            codeCounts: [:],
            startedAt: Date(),
            lastUpdatedAt: Date()
        )
        persistAll()
    }

    // ============================================================
    // MARK: - Finish (唯一の終了API)
    // ============================================================

    func finishCurrentSession(workType: WorkType) {
        switch workType {
        case .realtime:
            currentRealtimeSession = nil
            baseCode = nil

        case .kit:
            currentKitSession = nil

        case .scanStats:
            currentScanStatsSession = nil

        case .unlimited:
            // 互換用。SessionManager の作業種別としては使わない。
            return
        }

        persistAll()
    }

    // 互換
    func finishRealtimeSession() { finishCurrentSession(workType: .realtime) }
    func finishKitSession() { finishCurrentSession(workType: .kit) }
    func finishScanStatsSession() { finishCurrentSession(workType: .scanStats) }

    // ============================================================
    // MARK: - Suspend / Resume (最大1件 / 期限切れは自動削除)
    // ============================================================

    func suspendCurrentSession(workType: WorkType) {
        let payload: SuspendedPayload?

        switch workType {
        case .realtime:
            guard let s = currentRealtimeSession else { return }
            payload = .realtime(s)
            currentRealtimeSession = nil

        case .kit:
            guard let s = currentKitSession else { return }
            payload = .kit(s)
            currentKitSession = nil

        case .scanStats:
            guard let s = currentScanStatsSession else { return }
            payload = .scanStats(s)
            currentScanStatsSession = nil

        case .unlimited:
            // 互換用。SessionManager の作業種別としては使わない。
            return
        }

        guard let payload else { return }

        // ✅ 中断枠は最大1件
        //    既存の中断が Realtime で、別モード中断で上書きするなら Base Code も失効させる
        if workType != .realtime,
           let existing = suspendedSession {
            if case .realtime = existing.payload {
                baseCode = nil
            }
        }

        suspendedSession = SuspendedSession(savedAt: Date(), payload: payload)
        persistAll()
    }

    func discardSuspendedSession() {
        if let existing = suspendedSession {
            if case .realtime = existing.payload {
                baseCode = nil
            }
        }

        suspendedSession = nil
        persistAll()
    }

    func purgeExpiredSuspendedIfNeeded() {
        if let s = suspendedSession, s.isExpired {
            if case .realtime = s.payload {
                baseCode = nil
            }
            suspendedSession = nil
            persistAll()
        }
    }

    func remainingDaysForSuspendedSession() -> Int? {
        guard let s = suspendedSession else { return nil }
        return s.remainingDays
    }

    func resumeSuspendedSession(_ session: SuspendedSession) {
        if session.isExpired {
            if suspendedSession?.id == session.id {
                if case .realtime = session.payload {
                    baseCode = nil
                }
                suspendedSession = nil
                persistAll()
            }
            return
        }

        switch session.payload {
        case .realtime(let r):
            currentRealtimeSession = r

        case .kit(let k):
            currentKitSession = k

        case .scanStats(let s):
            currentScanStatsSession = s
        }

        if suspendedSession?.id == session.id {
            suspendedSession = nil
        }
        persistAll()
    }

    // ============================================================
    // MARK: - Testing helper
    // - テスト時に kitStore まで必ず初期化する
    // - これを呼ばないと Kit 定義が溜まり、上限5件で upsert が失敗して
    //   Kit系テストが連鎖崩壊する
    // ============================================================

    func resetAllStateForTesting() {
        baseCode = nil
        kitStore = KitStore()

        currentRealtimeSession = nil
        currentKitSession = nil
        currentScanStatsSession = nil

        suspendedSession = nil

        persistAll()
    }

    // ============================================================
    // MARK: - Persistence (UserDefaults / Codable)
    // - 失敗しても落とさない
    // - 状態全体を1キーで保存
    // - verificationScans 追加に伴うレガシーデコード対応あり
    // ============================================================

    private let ud = UserDefaults.standard

    /// 正本キー
    private let keyPersisted = "SessionManager.PersistedState"

    /// 旧キー（移行用）
    private let legacyKeyPersisted = "session_manager_persisted"

    // 現行
    private struct PersistedState: Codable {
        var baseCode: String?
        var kitStore: KitStore

        var currentRealtimeSession: RealtimeSession?
        var currentKitSession: KitSession?
        var currentScanStatsSession: ScanStatsSession?

        var suspendedSession: SuspendedSession?
    }

    // 旧形式（verificationScans無し）
    private struct LegacyRealtimeSession: Codable {
        let entitlementAtStart: CapturedEntitlement
        var lastScannedCode: String?
        var lastOutcome: VerificationOutcomeKind?
        let startedAt: Date
    }

    private struct LegacyPersistedState: Codable {
        var baseCode: String?
        var kitStore: KitStore

        var currentRealtimeSession: LegacyRealtimeSession?
        var currentKitSession: KitSession?
        var currentScanStatsSession: ScanStatsSession?

        var suspendedSession: SuspendedSession?
    }

    private func persistAll() {
        let state = PersistedState(
            baseCode: baseCode,
            kitStore: kitStore,
            currentRealtimeSession: currentRealtimeSession,
            currentKitSession: currentKitSession,
            currentScanStatsSession: currentScanStatsSession,
            suspendedSession: suspendedSession
        )

        do {
            let data = try JSONEncoder().encode(state)
            ud.set(data, forKey: keyPersisted)
        } catch {
            // 永続化失敗でも落とさない
        }
    }

    private func loadPersistedAll() {
        // ① 現行キー
        if let data = ud.data(forKey: keyPersisted) {
            if let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
                baseCode = state.baseCode
                kitStore = state.kitStore
                currentRealtimeSession = state.currentRealtimeSession
                currentKitSession = state.currentKitSession
                currentScanStatsSession = state.currentScanStatsSession
                suspendedSession = state.suspendedSession
                return
            }

            if let legacy = try? JSONDecoder().decode(LegacyPersistedState.self, from: data) {
                applyLegacyStateAndMigrate(legacy)
                return
            }
        }

        // ② 旧キー
        if let legacyData = ud.data(forKey: legacyKeyPersisted) {
            if let state = try? JSONDecoder().decode(PersistedState.self, from: legacyData) {
                baseCode = state.baseCode
                kitStore = state.kitStore
                currentRealtimeSession = state.currentRealtimeSession
                currentKitSession = state.currentKitSession
                currentScanStatsSession = state.currentScanStatsSession
                suspendedSession = state.suspendedSession

                persistAll()
                ud.removeObject(forKey: legacyKeyPersisted)
                return
            }

            if let legacy = try? JSONDecoder().decode(LegacyPersistedState.self, from: legacyData) {
                applyLegacyStateAndMigrate(legacy)
                ud.removeObject(forKey: legacyKeyPersisted)
                return
            }
        }

        // ③ どっちも無ければ何もしない
    }

    private func applyLegacyStateAndMigrate(_ legacy: LegacyPersistedState) {
        baseCode = legacy.baseCode
        kitStore = legacy.kitStore

        if let old = legacy.currentRealtimeSession {
            currentRealtimeSession = RealtimeSession(
                entitlementAtStart: old.entitlementAtStart,
                verificationScans: 0,
                lastScannedCode: old.lastScannedCode,
                lastOutcome: old.lastOutcome,
                startedAt: old.startedAt
            )
        } else {
            currentRealtimeSession = nil
        }

        currentKitSession = legacy.currentKitSession
        currentScanStatsSession = legacy.currentScanStatsSession
        suspendedSession = legacy.suspendedSession

        persistAll()
    }

    // ============================================================
    // MARK: - Common helpers
    // ============================================================

    /// 改行 / CR / タブ / 制御文字(0x00-0x1F) を拒否
    private func containsForbiddenControlChars(_ s: String) -> Bool {
        for u in s.unicodeScalars {
            if u.value == 0x0A || u.value == 0x0D || u.value == 0x09 || u.value < 0x20 {
                return true
            }
        }
        return false
    }
}
