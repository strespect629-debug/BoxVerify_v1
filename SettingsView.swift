import SwiftUI
import UIKit

@MainActor
struct SettingsView: View {

    // ✅ SSOT（参照のみ）
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    var body: some View {

        // ✅ snapshot固定（描画中のブレ防止）
        let snap = purchaseManager.diagnosticsSnapshot()

        Form {

            // =========================================================
            // システム
            // =========================================================
            Section("システム") {
                Button {
                    openSystemSettings()
                } label: {
                    Label("設定を開く", systemImage: "gearshape")
                }
            }

            // =========================================================
            // Kit 定義
            // =========================================================
            Section("Kit 定義（Kit Check用）") {
                NavigationLink {
                    KitLibraryView()
                } label: {
                    Label("Kit ID と構成品を登録/編集", systemImage: "shippingbox")
                }
            }

            // =========================================================
            // 購入
            // =========================================================
            Section("購入") {

                Toggle(isOn: $purchaseManager.autoVerifyEnabled) {
                    VStack(alignment: .leading, spacing: 4) {

                        Text("起動時/復帰時に購入状態を確認する")

                        Text("通信がある時のみ更新されます。オフライン時は最後の状態を使用します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: purchaseManager.autoVerifyEnabled) { _, _ in
                    Task {
                        await purchaseManager.autoVerifyIfEnabled()
                    }
                }

                NavigationLink {
                    PurchaseView()
                } label: {
                    Label("購入・課金へ", systemImage: "cart")
                }
            }

            // =========================================================
            // 状態
            // =========================================================
            Section("状態（参照）") {

                statusRow(
                    title: "権利状態",
                    value: entitlementStateLabel(snap.entitlementState)
                )

                statusRow(
                    title: "最終確認結果",
                    value: verificationLabel(snap.lastVerificationResult)
                )

                statusRow(
                    title: "最終確認日",
                    value: dateLabel(snap.lastVerifiedAt)
                )

                statusRow(
                    title: "オフライン猶予",
                    value: "\(snap.remainingDays) 日"
                )

                statusRow(
                    title: "有効プラン",
                    value: productsLabel(snap.lastKnownEntitlement)
                )
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Row

    @ViewBuilder
    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Labels

    private func entitlementStateLabel(_ state: EntitlementState) -> String {
        switch state {
        case .unknown:
            return "未確認"
        case .active:
            return "有効"
        case .inactive:
            return "未購入"
        }
    }

    private func verificationLabel(_ result: PurchaseVerificationResult?) -> String {
        guard let result else { return "未実施" }
        return result.kind == .success ? "成功" : "失敗"
    }

    private func productsLabel(_ entitlement: EntitlementSnapshot?) -> String {
        guard let e = entitlement else { return "なし" }

        let list = e.activeProducts.map {
            switch $0 {
            case .realtime: return "Realtime"
            case .scanStats: return "ScanStats"
            case .kit: return "Kit"
            }
        }

        return list.isEmpty ? "なし" : list.joined(separator: ", ")
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let d = date else { return "なし" }
        return Self.dateFormatter.string(from: d)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - System Settings

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
