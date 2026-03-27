import SwiftUI

// MARK: - CompleteMenuView（操作集約ハブ / 純View）
// ✅ 正本：CompleteMenuView は NavigationStack を内包しない（多重ナビ事故防止）
// ✅ 正本：sheet/overlay で表示する側が NavigationStack { CompleteMenuView(...) } で包むこと
struct CompleteMenuView: View {

    @Environment(\.dismiss) private var dismiss

    let workType: WorkType

    /// ✅ 終了/中断は「親Viewが責任を持って」実行する（showingMenu=false→停止→suspend/finish→親dismissまで）
    let onFinish: @MainActor () -> Void
    let onSuspend: @MainActor () -> Void

    // ✅ 診断（注入用）
    @State private var showingDiagnostics: Bool = false
    @State private var diagnosticsText: String = ""

    // ✅ 緊急手入力の遷移制御（NavigationLink直押しを避ける）
    @State private var navigateToEmergencyManual: Bool = false

    // ✅ SwiftUIの複数alert競合を避ける（1本化）
    @State private var activeAlert: ActiveAlert? = nil

    init(
        workType: WorkType,
        onFinish: @escaping @MainActor () -> Void,
        onSuspend: @escaping @MainActor () -> Void
    ) {
        self.workType = workType
        self.onFinish = onFinish
        self.onSuspend = onSuspend
    }

    var body: some View {
        List {

            // =========================
            // 作業
            // =========================
            Section("作業") {
                Button("終了（作業を終了して破棄）") {
                    activeAlert = .finishConfirm
                }
                .foregroundStyle(.red)

                Button("中断（保存してホームへ）") {
                    activeAlert = .suspendConfirm
                }
            }

            // =========================
            // 緊急用（Realtimeのみ）
            // =========================
            if workType == .realtime {
                Section("緊急用") {
                    Button("緊急手入力（Base Code / 照合コード）") {
                        handleOpenEmergencyManual()
                    }
                }
            }

            // =========================
            // 購入・設定
            // =========================
            Section("購入・設定") {
                NavigationLink("購入・課金（Purchase）") {
                    PurchaseView()
                }
                NavigationLink("設定（Settings）") {
                    SettingsView()
                }
            }

            // =========================
            // ヘルプ
            // =========================
            Section("ヘルプ") {
                // ✅ HelpView は「診断情報生成クロージャ注入」方式（SSOT保持なし）
                NavigationLink("Q&A / 問い合わせ") {
                    HelpView(
                        diagnosticsProvider: {
                            DiagnosticsManager.exportText(
                                sessionManager: SessionManager.shared,
                                purchaseManager: PurchaseManager.shared
                            )
                        }
                    )
                }

                Button("診断情報を見る") {
                    diagnosticsText = DiagnosticsManager.exportText(
                        sessionManager: SessionManager.shared,
                        purchaseManager: PurchaseManager.shared
                    )
                    showingDiagnostics = true
                }
            }
        }
        .navigationTitle("メニュー")
        .navigationBarTitleDisplayMode(.inline)

        // ✅ 閉じる（メニューを閉じるだけ。終了/中断は親が閉じるのでここは別用途）
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる") { dismiss() }
            }
        }

        // ✅ Realtimeのみ：緊急手入力の遷移
        // ※戻ると binding は自動で false へ戻るので、destination側の手動リセットは禁止
        .navigationDestination(isPresented: $navigateToEmergencyManual) {
            EmergencyManualInputView()
        }

        // ✅ alert 1本化
        .alert(item: $activeAlert) { item in
            switch item {

            case .finishConfirm:
                return Alert(
                    title: Text("作業を終了して破棄しますか？"),
                    message: Text("この作業は復元できません。"),
                    primaryButton: .destructive(Text("破棄して終了")) {
                        // ✅ 重要：ここで dismiss() しない（メニューsheetだけ閉じて作業画面が残る事故の元）
                        Task { @MainActor in
                            onFinish()
                        }
                    },
                    secondaryButton: .cancel(Text("キャンセル"))
                )

            case .suspendConfirm:
                return Alert(
                    title: Text("中断して保存しますか？"),
                    message: Text("中断データは最大1件・7日で自動的に削除される場合があります。"),
                    primaryButton: .default(Text("中断する")) {
                        // ✅ 重要：ここで dismiss() しない（メニューsheetだけ閉じて作業画面が残る事故の元）
                        Task { @MainActor in
                            onSuspend()
                        }
                    },
                    secondaryButton: .cancel(Text("キャンセル"))
                )

            case .emergencyBlocked:
                return Alert(
                    title: Text("本日の無料利用は終了しました"),
                    message: Text("無料で判定結果を表示できるのは1日1回までです。続けるには Realtime の購入が必要です。"),
                    dismissButton: .cancel(Text("OK"))
                )
            }
        }

        // ✅ 診断（注入式 / DiagnosticsView()禁止）
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView(diagnosticsText: diagnosticsText)
        }
    }

    // MARK: - Emergency gate
    private func handleOpenEmergencyManual() {
        // ✅ 安全：Realtime以外からは絶対に通さない
        guard workType == .realtime else { return }

        // ✅ 状態ズレ防止：必ず日付更新チェック
        RealtimeTrialLimiter.resetIfNewDay()

        // ✅ 正本：Realtimeの権利判定は realtimeAccess（unlimitedAccess参照禁止）
        if PurchaseManager.shared.realtimeAccess.isAllowed {
            navigateToEmergencyManual = true
            return
        }

        // ✅ 未購入(trial)は上限到達ならブロック、それ以外は遷移OK
        let s = RealtimeTrialLimiter.status()
        if s.isExhausted {
            activeAlert = .emergencyBlocked
            return
        }

        navigateToEmergencyManual = true
    }

    // MARK: - ActiveAlert
    private enum ActiveAlert: Identifiable {
        case finishConfirm
        case suspendConfirm
        case emergencyBlocked

        var id: String {
            switch self {
            case .finishConfirm: return "finishConfirm"
            case .suspendConfirm: return "suspendConfirm"
            case .emergencyBlocked: return "emergencyBlocked"
            }
        }
    }
}
