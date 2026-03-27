import SwiftUI

// MARK: - KitLibraryView（Kit定義の一覧・追加・編集）
// ✅ Models.swift 正本前提：
// - KitStore.definitions: [String: KitDefinition] （key=kitId）
// - KitDefinition: { id: UUID, kitId: String, requiredCounts: [String:Int] }
// - 事故防止：最大キット数 / 1キット最大項目数 / 1項目最大数量 を固定
// ✅ 追加仕様（正式）：無課金は Kit登録「最大1件」までOK（編集は可）
struct KitLibraryView: View {

    @ObservedObject private var sessionManager: SessionManager = .shared
    @ObservedObject private var purchaseManager: PurchaseManager = .shared

    // 上限（正本）
    private let paidMaxKitsAllowed = 5
    private let unpaidMaxKitsAllowed = 1
    private let maxItemsPerKit = 5
    private let maxQuantityPerItem = 30

    @State private var showingRegisterSheet = false
    @State private var editingKitId: String? = nil

    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showingAlert = false

    // ✅ 無課金=1件 / 有料=5件
    private var maxKitsAllowed: Int {
        purchaseManager.kitAccess.isAllowed ? paidMaxKitsAllowed : unpaidMaxKitsAllowed
    }

    private var kits: [KitDefinition] {
        Array(sessionManager.kitStore.definitions.values)
            .sorted { $0.kitId.localizedStandardCompare($1.kitId) == .orderedAscending }
    }

    private var canAddNewKit: Bool {
        kits.count < maxKitsAllowed
    }

    private var isEmpty: Bool {
        kits.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kit がまだ登録されていません")
                                .font(.headline)

                            Text("右上の＋から Kit ID と構成品コード（必要数）を登録してください。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text(limitFootnoteText())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(kits, id: \.kitId) { def in
                            KitRow(definition: def)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingKitId = def.kitId
                                    showingRegisterSheet = true
                                }
                        }
                        .onDelete(perform: deleteKits)
                    }
                } header: {
                    Text("Kit Library")
                } footer: {
                    Text(limitFootnoteText())
                }
            }
            .navigationTitle("Kit Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingKitId = nil

                        guard canAddNewKit else {
                            showAlert(
                                title: "上限に達しました",
                                message: maxKitsAllowed == 1
                                    ? "無課金では Kit は最大 1 件まで登録できます。有料プランで最大 5 件まで増やせます。"
                                    : "Kit は最大 \(maxKitsAllowed) 件までです。不要なKitを削除してから追加してください。"
                            )
                            return
                        }

                        showingRegisterSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Kitを追加")
                }
            }
            .sheet(isPresented: $showingRegisterSheet, onDismiss: {
                // ✅ 閉じたら編集対象をクリア（事故防止）
                editingKitId = nil
            }) {
                KitRegisterSheet(
                    maxItemsPerKit: maxItemsPerKit,
                    maxKitsAllowed: maxKitsAllowed,
                    currentKitCount: kits.count,
                    maxQuantityPerItem: maxQuantityPerItem,
                    editing: editingKitId.flatMap { sessionManager.kitStore.definitions[$0] },
                    onSave: { kitId, requiredCounts in
                        upsertKit(kitId: kitId, requiredCounts: requiredCounts)
                        showingRegisterSheet = false
                    },
                    onCancel: {
                        showingRegisterSheet = false
                    },
                    onError: { title, message in
                        // ✅ 互換維持：親alertも残す（通常はシート側で表示）
                        showAlert(title: title, message: message)
                    }
                )
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func limitFootnoteText() -> String {
        if maxKitsAllowed == 1 {
            return "無課金：最大 1 キット / 1キット最大 \(maxItemsPerKit)項目 / 1項目最大 \(maxQuantityPerItem) 個（有料で最大 5 キット）"
        } else {
            return "制限：最大 \(maxKitsAllowed)キット / 1キット最大 \(maxItemsPerKit)項目 / 1項目最大 \(maxQuantityPerItem) 個"
        }
    }

    // MARK: - CRUD
    private func upsertKit(kitId: String, requiredCounts: [String: Int]) {
        let trimmedKitId = kitId.trimmingCharacters(in: .whitespacesAndNewlines)

        let exists = sessionManager.kitStore.definitions[trimmedKitId] != nil
        if !exists && !canAddNewKit {
            showAlert(
                title: "上限に達しました",
                message: maxKitsAllowed == 1
                    ? "無課金では Kit は最大 1 件まで登録できます。有料プランで最大 5 件まで増やせます。"
                    : "Kit は最大 \(maxKitsAllowed) 件までです。"
            )
            return
        }

        // ✅ SSOT APIを呼ぶ（Viewから直接書き換えない）
        // ✅ 無課金=1件 / 有料=5件 を SSOT側でも強制
        sessionManager.upsertKit(
            kitId: trimmedKitId,
            requiredCounts: requiredCounts,
            maxKitsAllowedOverride: maxKitsAllowed
        )
    }

    private func deleteKits(at offsets: IndexSet) {
        let targets = offsets.map { kits[$0].kitId }
        for kitId in targets {
            // ✅ SSOT APIを呼ぶ
            sessionManager.deleteKit(kitId: kitId)
        }
    }

    // MARK: - Alert helper
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

// MARK: - Row
private struct KitRow: View {
    let definition: KitDefinition

    private var itemCount: Int { definition.requiredCounts.count }
    private var totalRequired: Int { definition.requiredCounts.values.reduce(0, +) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.kitId)
                    .font(.headline)

                Text("項目数 \(itemCount) / 合計必要数 \(totalRequired)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Register/Edit Sheet
private struct KitRegisterSheet: View {

    let maxItemsPerKit: Int
    let maxKitsAllowed: Int
    let currentKitCount: Int
    let maxQuantityPerItem: Int

    let editing: KitDefinition?

    let onSave: (_ kitId: String, _ requiredCounts: [String: Int]) -> Void
    let onCancel: () -> Void
    let onError: (_ title: String, _ message: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kitId: String = ""
    @State private var rows: [ItemRow] = []

    // ✅ 重要：シート内でアラートを出して画面遷移/戻りを防ぐ
    @State private var localAlertTitle: String = ""
    @State private var localAlertMessage: String = ""
    @State private var showingLocalAlert: Bool = false

    struct ItemRow: Identifiable, Hashable {
        let id = UUID()
        var code: String
        var qty: Int
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Kit ID") {
                    TextField("例：KIT-A", text: $kitId)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)

                    if editing != nil {
                        Text("編集モード：既存Kitを上書き保存します")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("新規追加：最大 \(maxKitsAllowed) 件（現在 \(currentKitCount) 件）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("構成品（最大 \(maxItemsPerKit) 項目 / 1項目最大 \(maxQuantityPerItem) 個）") {
                    if rows.isEmpty {
                        Text("「＋項目追加」から構成品コードと必要数を登録してください。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($rows) { $row in
                            HStack {
                                TextField("構成品コード", text: $row.code)
                                    .textInputAutocapitalization(.characters)
                                    .disableAutocorrection(true)

                                Spacer()

                                Stepper(value: $row.qty, in: 1...maxQuantityPerItem) {
                                    Text("\(row.qty)")
                                        .monospacedDigit()
                                }
                                .frame(width: 140)
                            }
                        }
                        .onDelete { indexSet in
                            rows.remove(atOffsets: indexSet)
                        }
                    }

                    Button {
                        // ✅ 上限到達時は「この画面のまま」アラート表示して終了（戻らない）
                        guard rows.count < maxItemsPerKit else {
                            presentLocalAlert(
                                title: "上限に達しました",
                                message: "1キットあたり最大 \(maxItemsPerKit) 項目までです。"
                            )
                            return
                        }
                        rows.append(.init(code: "", qty: 1))
                    } label: {
                        Label("項目追加", systemImage: "plus.circle")
                    }
                }

                Section("プレビュー") {
                    let dict = buildRequiredCountsPreview()
                    if dict.isEmpty {
                        Text("まだ有効な項目がありません")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dict.keys.sorted(), id: \.self) { key in
                            HStack {
                                Text(key)
                                Spacer()
                                Text("× \(dict[key] ?? 0)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Kitを追加" : "Kitを編集")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        handleSave()
                    }
                }
            }
            .onAppear {
                if let editing {
                    kitId = editing.kitId
                    rows = editing.requiredCounts
                        .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                        .map { ItemRow(code: $0.key, qty: min($0.value, maxQuantityPerItem)) }
                } else if rows.isEmpty {
                    rows = [ItemRow(code: "", qty: 1)]
                }
            }
            // ✅ シート内アラート（戻らない）
            .alert(localAlertTitle, isPresented: $showingLocalAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(localAlertMessage)
            }
        }
    }

    private func handleSave() {
        let trimmedKitId = kitId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKitId.isEmpty else {
            presentLocalAlert(title: "入力不足", message: "Kit ID を入力してください。")
            return
        }

        if trimmedKitId.contains("\n") || trimmedKitId.contains("\r") {
            presentLocalAlert(title: "不正なKit ID", message: "Kit ID に改行が含まれています。改行を削除してください。")
            return
        }

        let requiredCounts = buildRequiredCountsPreview()

        guard !requiredCounts.isEmpty else {
            presentLocalAlert(title: "入力不足", message: "構成品を1つ以上登録してください。")
            return
        }

        onSave(trimmedKitId, requiredCounts)
    }

    private func buildRequiredCountsPreview() -> [String: Int] {
        var dict: [String: Int] = [:]

        for r in rows {
            let code = r.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }

            if code.contains("\n") || code.contains("\r") {
                continue
            }

            dict[code] = min(max(1, r.qty), maxQuantityPerItem)
        }

        // 念のため：上限超過は先頭から切り詰め
        if dict.count > maxItemsPerKit {
            let keys = dict.keys.sorted()
            let allowed = Set(keys.prefix(maxItemsPerKit))
            dict = dict.filter { allowed.contains($0.key) }
        }

        return dict
    }

    // MARK: - Local Alert
    private func presentLocalAlert(title: String, message: String) {
        localAlertTitle = title
        localAlertMessage = message
        showingLocalAlert = true
    }
}
