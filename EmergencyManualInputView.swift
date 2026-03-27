import SwiftUI

// MARK: - EmergencyManualInputView（Realtime専用 / 緊急手入力）
// ✅ 正本ルール：Realtime未購入（trial）の場合は RealtimeTrialLimiter に必ず従属
// - 上限到達日は「Base Code登録」も「手入力照合」も実行しない（結果表示もしない）
// - 判定結果を表示した場合のみ recordAttempt() を消費
// - trialで判定した直後は Base Code を自動解除（スキャンと同一）
@MainActor
struct EmergencyManualInputView: View {

    @ObservedObject private var sessionManager = SessionManager.shared
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    // ✅ Base Code 手入力は「2回入力（確認用）」必須
    @State private var baseCodeInput: String = ""
    @State private var baseCodeConfirmInput: String = ""

    // 照合入力
    @State private var verifyCodeInput: String = ""

    // 表示
    @State private var showingResult: Bool = false
    @State private var outcomeKind: VerificationOutcomeKind = .notJudged
    @State private var resultTitle: String = ""
    @State private var resultMessage: String = ""

    // ✅ fullScreenCover 自動クローズ不安定対策：表示ごとに更新するトークン
    @State private var resultToken: UUID = UUID()

    // アラート（上限到達/入力不備）
    @State private var showingAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""

    // ✅ 正本：Realtime の権利判定は realtimeAccess（unlimitedAccess参照禁止）
    private var canUseRealtime: Bool { purchaseManager.realtimeAccess.isAllowed }
    private var isTrialMode: Bool { !canUseRealtime }

    // ✅ Base Code 登録ボタンの有効条件（2回入力が一致）
    private var canRegisterBaseCode: Bool {
        let a = baseCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = baseCodeConfirmInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return !a.isEmpty && a == b
    }

    var body: some View {
        Form {

            Section("注意（緊急用）") {
                Text("通常はスキャンを使用してください。ここはカメラが使えない等の緊急時のみです。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if isTrialMode {
                    Text("※無課金（trial）では、判定結果を表示できる回数に上限があります。上限到達日は手入力でも判定できません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Base Code（基準コード）") {
                VStack(alignment: .leading, spacing: 10) {

                    TextField("Base Code を入力（1回目）", text: $baseCodeInput)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    TextField("Base Code を入力（確認用）", text: $baseCodeConfirmInput)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    if !baseCodeConfirmInput.isEmpty && !canRegisterBaseCode {
                        Text("※2回の入力が一致しません")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("登録") {
                        registerBaseCodeByManual()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRegisterBaseCode)
                }

                HStack {
                    Text("現在：")
                    Text(sessionManager.baseCode ?? "未登録")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button(role: .destructive) {
                    _ = sessionManager.setBaseCode(nil)
                    baseCodeInput = ""
                    baseCodeConfirmInput = ""
                } label: {
                    Text("Base Code を解除")
                }
            }

            Section("照合（手入力）") {
                HStack {
                    TextField("照合するコードを入力", text: $verifyCodeInput)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    Button("判定") {
                        verifyByManual()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if isTrialMode {
                    Text("無料で判定結果を表示できる回数には上限があります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("緊急手入力（Realtime）")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 日付切替のリセット＋上限ならBase Code保持しない
            RealtimeTrialLimiter.resetIfNewDay()
            enforceTrialIfExhausted()
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .fullScreenCover(isPresented: $showingResult) {
            ResultFullScreenView(
                title: resultTitle,
                message: resultMessage,
                kind: outcomeKind,
                autoCloseSeconds: (outcomeKind == .ok ? 1.2 : nil), // ✅ OKだけ自動クローズ
                token: resultToken,
                contextItems: []
            ) {
                closeResult()
            }
        }
    }

    // MARK: - Trial enforcement
    private func enforceTrialIfExhausted() {
        guard isTrialMode else { return }
        let s = RealtimeTrialLimiter.status()
        if s.isExhausted {
            // ✅ 上限到達日は Base Code を保持しない（スキャンと同一思想）
            if sessionManager.baseCode != nil {
                _ = sessionManager.setBaseCode(nil)
            }
        }
    }

    private func guardTrialAvailabilityOrAlert() -> Bool {
        guard isTrialMode else { return true }

        RealtimeTrialLimiter.resetIfNewDay()
        let s = RealtimeTrialLimiter.status()
        if s.isExhausted {
            enforceTrialIfExhausted()
            showAlert(
                title: "本日の無料利用は終了しました",
                message: "無料で判定結果を表示できるのは1日1回までです。続けるには Realtime の購入が必要です。"
            )
            return false
        }
        return true
    }

    // MARK: - Actions
    private func registerBaseCodeByManual() {
        // ✅ trial上限日は Base Code登録も禁止（結果表示もしない）
        guard guardTrialAvailabilityOrAlert() else { return }

        let code = baseCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirm = baseCodeConfirmInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !code.isEmpty else {
            showAlert(title: "入力不足", message: "Base Code を入力してください。")
            return
        }
        guard code == confirm else {
            showAlert(title: "入力不一致", message: "Base Code の2回入力が一致しません。もう一度確認してください。")
            return
        }

        let ok = sessionManager.setBaseCode(code)
        if ok {
            outcomeKind = .ok
            resultTitle = "Base Code を登録しました"
            resultMessage = "次は照合したいコードを入力して判定してください。"
        } else {
            outcomeKind = .ng
            resultTitle = "登録できません"
            resultMessage = "改行・タブなどの制御文字が含まれている可能性があります。"
        }

        // ✅ 入力欄は登録後にクリア（事故防止）
        baseCodeInput = ""
        baseCodeConfirmInput = ""

        // ✅ 表示ごとにtoken更新（自動クローズ不安定対策）
        resultToken = UUID()
        showingResult = true
    }

    private func verifyByManual() {
        // ✅ trial上限日は 手入力判定も禁止（結果表示もしない）
        guard guardTrialAvailabilityOrAlert() else { return }

        guard let base = sessionManager.baseCode, !base.isEmpty else {
            showAlert(title: "Base Code 未登録", message: "先に Base Code を登録してください。")
            return
        }

        let code = verifyCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            showAlert(title: "入力不足", message: "照合するコードを入力してください。")
            return
        }

        let ok = (code == base)
        outcomeKind = ok ? .ok : .ng
        resultTitle = ok ? "OK" : "NG"
        resultMessage = ok ? "一致しました" : "一致しません"

        // ✅ ここが「照合判定」→ ここだけ SSOTで +1
        sessionManager.recordRealtimeVerification(code: code, outcome: outcomeKind)

        // ✅ trial：判定結果を出したら回数消費＋Base Code 強制解除（スキャンと同一）
        if isTrialMode {
            _ = RealtimeTrialLimiter.recordAttempt()
            _ = sessionManager.setBaseCode(nil)
            enforceTrialIfExhausted()
        }

        // ✅ 入力欄クリア（事故防止）
        verifyCodeInput = ""

        // ✅ 表示ごとにtoken更新（自動クローズ不安定対策）
        resultToken = UUID()
        showingResult = true
    }

    private func closeResult() {
        showingResult = false
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}
