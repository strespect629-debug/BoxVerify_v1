import Foundation

// =====================================================
// MARK: - DiagnosticsManager（正本）
// - singleton(shared) 廃止
// - 「その場生成・履歴保持なし」
// - 生成口は static func exportText(...) ただ1つ
// - 文言/コメントに「v1」を入れない
// =====================================================

enum DiagnosticsManager {

    static func exportText(
        sessionManager: SessionManager,
        purchaseManager: PurchaseManager
    ) -> String {

        let now = Date()

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // ---- helpers ----
        func sanitize(_ s: String) -> String {
            return s
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t")
        }

        func fmt(_ value: String?) -> String {
            guard let value, !value.isEmpty else { return "(nil)" }
            return sanitize(value)
        }

        func fmtBool(_ b: Bool) -> String {
            return b ? "true" : "false"
        }

        func fmtDate(_ d: Date?) -> String {
            guard let d else { return "(nil)" }
            return iso.string(from: d)
        }

        func line(_ k: String, _ v: String) -> String {
            return "\(k)=\(v)"
        }

        // ---- build ----
        var lines: [String] = []
        lines.append("=== BoxVerify Diagnostics ===")
        lines.append(line("generatedAt", iso.string(from: now)))
        lines.append("")

        // -------------------------
        // App
        // -------------------------
        let bundle = Bundle.main
        let appVer = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"

        lines.append("[App]")
        lines.append(line("version", "\(sanitize(appVer)) (\(sanitize(build)))"))
        lines.append("")

        // -------------------------
        // SessionManager (SSOT)
        // -------------------------
        lines.append("[SessionManager]")
        lines.append(line("baseCode", fmt(sessionManager.baseCode)))
        lines.append(line("kitDefinitions", "\(sessionManager.kitDefinitionsCount())"))

        let realtimeYesNo = sessionManager.currentRealtimeSession != nil ? "yes" : "no"
        let kitYesNo = sessionManager.currentKitSession != nil ? "yes" : "no"
        let scanStatsYesNo = sessionManager.currentScanStatsSession != nil ? "yes" : "no"

        lines.append(line("currentRealtimeSession", realtimeYesNo))
        lines.append(line("currentKitSession", kitYesNo))
        lines.append(line("currentScanStatsSession", scanStatsYesNo))

        if let r = sessionManager.currentRealtimeSession {
            lines.append(line("realtimeSession.startedAt", iso.string(from: r.startedAt)))
            lines.append(line("realtimeSession.verificationScans", "\(r.verificationScans)"))
            lines.append(line("realtimeSession.lastScannedCode", fmt(r.lastScannedCode)))
            lines.append(line("realtimeSession.lastOutcome", fmt(r.lastOutcome?.rawValue)))
        } else {
            lines.append(line("realtimeSessionDetail", "(nil)"))
        }

        if let s = sessionManager.suspendedSession {
            lines.append(line("suspendedSession", "yes"))
            lines.append(line("suspendedSavedAt", iso.string(from: s.savedAt)))
            lines.append(line("suspendedRemainingDays", "\(s.remainingDays)"))

            let expiredYesNo = s.isExpired ? "yes" : "no"
            lines.append(line("suspendedExpired", expiredYesNo))
        } else {
            lines.append(line("suspendedSession", "no"))
        }

        lines.append("")

        // -------------------------
        // PurchaseManager (SSOT)
        // -------------------------
        lines.append("[PurchaseManager]")

        let snap = purchaseManager.diagnosticsSnapshot()

        lines.append(line("entitlementState", sanitize(snap.entitlementState.rawValue)))
        lines.append(line("autoVerifyEnabled", fmtBool(snap.autoVerifyEnabled)))
        lines.append(line("remainingDays", "\(snap.remainingDays)"))
        lines.append(line("lastVerifiedAt", fmtDate(snap.lastVerifiedAt)))

        if let r = snap.lastVerificationResult {
            lines.append(line("lastVerificationResult.kind", sanitize(r.kind.rawValue)))
            lines.append(line("lastVerificationResult.at", iso.string(from: r.at)))
            lines.append(line("lastVerificationResult.message", fmt(r.message)))
        } else {
            lines.append(line("lastVerificationResult", "(nil)"))
        }

        if let ent = snap.lastKnownEntitlement {
            let names = ent.activeProducts.map { $0.rawValue }.sorted()
            let joined = names.joined(separator: ",")

            lines.append(line(
                "lastKnownEntitlement.activeProducts",
                names.isEmpty ? "[]" : sanitize(joined)
            ))
        } else {
            lines.append(line("lastKnownEntitlement", "(nil)"))
        }

        // -------------------------
        // Productロード状況
        // -------------------------
        let loadedKinds = purchaseManager.loadedProductKinds().map { $0.rawValue }.sorted()
        let loadedProductIDs = purchaseManager.loadedProductIDs()

        let cachedPairs = purchaseManager.cachedProductIDsByKind()
            .map { key, value in "\(key.rawValue):\(value)" }
            .sorted()

        lines.append(line(
            "loadedProductKinds",
            loadedKinds.isEmpty ? "[]" : sanitize(loadedKinds.joined(separator: ","))
        ))

        lines.append(line(
            "loadedProductIDs",
            loadedProductIDs.isEmpty ? "[]" : sanitize(loadedProductIDs.joined(separator: ","))
        ))

        lines.append(line(
            "cachedProductIDsByKind",
            cachedPairs.isEmpty ? "[]" : sanitize(cachedPairs.joined(separator: ","))
        ))

        // -------------------------
        // 🔥 StoreKit実測データ（超重要）
        // -------------------------
        let entitlementIDs = purchaseManager.lastEntitlementProductIDsDebug()
        let subscriptionStates = purchaseManager.lastSubscriptionStatesByIDDebug()
        let activeKindsDebug = purchaseManager.lastActiveKindsDebugValues()

        lines.append(line(
            "entitlementProductIDs",
            entitlementIDs.isEmpty ? "[]" : sanitize(entitlementIDs.joined(separator: ","))
        ))

        let subscriptionPairs = subscriptionStates
            .map { key, value in "\(key):\(value)" }
            .sorted()

        lines.append(line(
            "subscriptionStates",
            subscriptionPairs.isEmpty ? "[]" : sanitize(subscriptionPairs.joined(separator: ","))
        ))

        lines.append(line(
            "activeKindsDebug",
            activeKindsDebug.isEmpty ? "[]" : sanitize(activeKindsDebug.joined(separator: ","))
        ))

        lines.append("")

        // -------------------------
        // FeatureAccess（最終判定）
        // -------------------------
        lines.append("[FeatureAccess]")

        lines.append(line(
            "realtimeAccess.allowed",
            fmtBool(purchaseManager.realtimeAccess.isAllowed)
        ))
        lines.append(line(
            "realtimeAccess.reason",
            sanitize(String(describing: purchaseManager.realtimeAccess.reason))
        ))

        lines.append(line(
            "scanStatsAccess.allowed",
            fmtBool(purchaseManager.scanStatsAccess.isAllowed)
        ))
        lines.append(line(
            "scanStatsAccess.reason",
            sanitize(String(describing: purchaseManager.scanStatsAccess.reason))
        ))

        lines.append(line(
            "kitAccess.allowed",
            fmtBool(purchaseManager.kitAccess.isAllowed)
        ))
        lines.append(line(
            "kitAccess.reason",
            sanitize(String(describing: purchaseManager.kitAccess.reason))
        ))

        lines.append("")
        lines.append("=== end ===")

        return lines.joined(separator: "\n")
    }
}
