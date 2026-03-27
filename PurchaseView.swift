import SwiftUI
import StoreKit

@MainActor
struct PurchaseView: View {

    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss

    private let showsCloseButton: Bool

    @State private var alertMessage: String? = nil
    @State private var showingAlert: Bool = false

    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    // ✅ 正本 Product IDs
    private let productIDsByKind: [ProductKind: String] = [
        .realtime: "com.boxverify.app.realtime.sub",
        .scanStats: "com.boxverify.app.scanstats.sub",
        .kit: "com.boxverify.app.kit"
    ]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {

        let snapshot = purchaseManager.diagnosticsSnapshot()

        List {

            // =========================
            // 購入状態
            // =========================
            Section("購入状態") {

                row("状態", value: stateLabel(snapshot.entitlementState))
                row("最終確認結果", value: verificationLabel(snapshot.lastVerificationResult))
                row("最終確認日", value: dateLabel(snapshot.lastVerifiedAt))

                if snapshot.entitlementState == .active {
                    row("オフライン猶予", value: "\(snapshot.remainingDays) 日")
                    row("有効プラン", value: productsLabel(snapshot.lastKnownEntitlement))
                }

                if let message = snapshot.lastVerificationResult?.message,
                   !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // =========================
            // 操作
            // =========================
            Section("操作") {

                Button {
                    Task {
                        await purchaseManager.loadProducts(productIDsByKind: productIDsByKind)
                        showResult()
                    }
                } label: {
                    HStack {
                        Text("価格情報を更新")
                        Spacer()
                        if purchaseManager.isLoadingProducts {
                            ProgressView()
                        }
                    }
                }

                Button {
                    Task {
                        await purchaseManager.restorePurchasesByUserAction()
                        showResult()
                    }
                } label: {
                    Text("購入を復元")
                }

                Button {
                    Task {
                        await purchaseManager.refreshEntitlements()
                        showResult()
                    }
                } label: {
                    Text("購入状態を再確認")
                }

                Button {
                    show("""
通信可能な状態で再起動 → 復元を実行してください。
改善しない場合は診断情報付きで問い合わせしてください。
""")
                } label: {
                    Text("購入が反映されない場合")
                }
            }

            // =========================
            // プラン
            // =========================
            Section("プラン") {

                planRow(
                    title: "Realtime",
                    subtitle: "1日1回制限を解除",
                    kind: .realtime,
                    isAllowed: purchaseManager.realtimeAccess.isAllowed
                )

                planRow(
                    title: "Scan Stats",
                    subtitle: "棚卸・集計機能",
                    kind: .scanStats,
                    isAllowed: purchaseManager.scanStatsAccess.isAllowed
                )

                planRow(
                    title: "Kit",
                    subtitle: "構成品チェック",
                    kind: .kit,
                    isAllowed: purchaseManager.kitAccess.isAllowed
                )
            }

            // =========================
            // 🔥 サブスク説明（必須）
            // =========================
            Section("サブスクリプション情報") {
                Text("""
本アプリは自動更新サブスクリプションを提供します。

・1ヶ月ごとに自動更新されます
・期間終了の24時間前までに解約しない限り自動更新されます
・購入はApple IDに課金されます
・サブスクリプションは設定アプリ > Apple ID > サブスクリプション から管理・解約できます
""")
                .font(.footnote)
            }

            // =========================
            // 🔥 規約リンク（必須）
            // =========================
            Section("規約") {

                Link(
                    "利用規約（Terms of Use）",
                    destination: URL(string: "https://boiling-wasp-cca.notion.site/Terms-of-Use-EULA-32db916b024b80feaa00fccf818300b2")!
                )

                Link(
                    "プライバシーポリシー",
                    destination: URL(string: "https://boiling-wasp-cca.notion.site/32db916b024b80a6a0fde01163fa9b0b")!
                )
            }
        }
        .navigationTitle("購入・課金")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task {
            await purchaseManager.loadProductsIfNeeded(productIDsByKind: productIDsByKind)
        }
        .alert("購入", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Plan Row

    private func planRow(
        title: String,
        subtitle: String,
        kind: ProductKind,
        isAllowed: Bool
    ) -> some View {

        let price = displayPriceText(for: kind)

        return VStack(alignment: .leading, spacing: 10) {

            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(isAllowed ? "有効" : "未購入")
                    .foregroundStyle(isAllowed ? .green : .secondary)
            }

            Text(subtitle)
                .font(.subheadline)

            HStack {

                Text(price)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        await purchaseManager.purchase(
                            kind: kind,
                            productIDsByKind: productIDsByKind
                        )
                        showResult()
                    }
                } label: {
                    Text(isAllowed ? "購入済み" : "購入する")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isAllowed ||
                    purchaseManager.isPurchasing ||
                    purchaseManager.productsByKind[kind] == nil
                )
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func showResult() {
        if let message = purchaseManager.lastVerificationResult?.message {
            show(message)
        } else {
            show("処理完了")
        }
    }

    private func displayPriceText(for kind: ProductKind) -> String {
        if let p = purchaseManager.productsByKind[kind] {
            return p.displayPrice
        }
        return purchaseManager.isLoadingProducts ? "取得中…" : "価格不明"
    }

    private func show(_ message: String) {
        alertMessage = message
        showingAlert = true
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func stateLabel(_ state: EntitlementState) -> String {
        switch state {
        case .unknown: return "未確認"
        case .active: return "有効"
        case .inactive: return "未購入"
        }
    }

    private func productsLabel(_ entitlement: EntitlementSnapshot?) -> String {
        guard let e = entitlement else { return "なし" }
        return e.activeProducts.map { productLabel($0) }.joined(separator: ", ")
    }

    private func productLabel(_ kind: ProductKind) -> String {
        switch kind {
        case .realtime: return "Realtime"
        case .scanStats: return "Scan Stats"
        case .kit: return "Kit"
        }
    }

    private func verificationLabel(_ result: PurchaseVerificationResult?) -> String {
        guard let result else { return "未実施" }
        return result.kind == .success ? "成功" : "失敗"
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let d = date else { return "なし" }
        return Self.dateFormatter.string(from: d)
    }
}
