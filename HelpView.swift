import SwiftUI

// MARK: - HelpView (Q&A)
struct HelpView: View {

    // 「Q&Aを読んだ」→「未解決」になった時だけ問い合わせ導線を出す
    @State private var didReadQA: Bool = false
    @State private var didSolve: Bool = true
    @State private var showFollowup: Bool = false
    @State private var showMailComposer: Bool = false
    @State private var showMailUnavailable: Bool = false

    // 検索
    @State private var query: String = ""

    // 診断情報（本文に埋め込む）
    var diagnosticsProvider: () -> String = { "" }

    // 宛先
    var supportEmail: String = "support@boxverify.app"

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                mainContent
                    .foregroundStyle(.primary)
            }
            .navigationTitle("Help / Q&A")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showMailComposer) {
                MailComposerView(
                    recipients: [supportEmail],
                    subject: "BoxVerify 問い合わせ",
                    body: composedMailBody(),
                    onFinish: { _ in
                        showMailComposer = false
                    }
                )
            }
            .alert("メールを開けません", isPresented: $showMailUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("この端末ではメール送信が利用できません。メール設定をご確認ください。")
            }
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 12) {

            TextField("検索（例：購入 / 未確認 / オフライン / 中断 / NG / Base Code）", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.top, 8)
                .foregroundStyle(.primary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Q&A")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)

                        Text("困ったときは、まず該当項目を検索してください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(HelpCategory.allCases, id: \.self) { category in
                            let items = groupedItems[category] ?? []
                            if !items.isEmpty {
                                Text(category.displayTitle)
                                    .font(.headline.bold())
                                    .padding(.horizontal)
                                    .padding(.top, 6)

                                VStack(spacing: 10) {
                                    ForEach(items, id: \.id) { item in
                                        DisclosureGroup {
                                            Text(item.answer)
                                                .font(.body)
                                                .foregroundStyle(.secondary)
                                                .padding(.top, 6)
                                        } label: {
                                            Text(item.question)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                        }
                                        .tint(.primary)
                                        .padding()
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $didReadQA) {
                            Text("Q&Aを確認しました")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .tint(.blue)

                        Text("問い合わせは Q&A を確認したうえで、解決しない場合のみ送信できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            showFollowup.toggle()
                        } label: {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                Text("解決しましたか？")
                                    .bold()
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        if showFollowup {
                            Picker("解決しましたか？", selection: $didSolve) {
                                Text("はい").tag(true)
                                Text("いいえ").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .tint(.blue)

                            if didReadQA && !didSolve {
                                Text("未解決の場合は、診断情報を添付してメールを作成できます。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    openMail()
                                } label: {
                                    HStack {
                                        Image(systemName: "envelope")
                                        Text("メールを作成する（診断情報付き）")
                                            .bold()
                                        Spacer()
                                    }
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            } else if !didReadQA && !didSolve {
                                Text("まずは Q&A を確認してください。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Mail
    private func openMail() {
        guard MailComposerView.canSendMail() else {
            showMailUnavailable = true
            return
        }
        showMailComposer = true
    }

    private func composedMailBody() -> String {
        let diag = diagnosticsProvider()
        return """

お問い合わせ内容：
（ここに状況を入力してください）

---

## 診断情報（自動添付）：
\(diag.isEmpty ? "（診断情報は未取得です）" : diag)
"""
    }

    // MARK: - Data Binding
    private var filteredItems: [HelpQAData.QAItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return HelpQAData.items }
        return HelpQAData.items.filter {
            $0.question.localizedCaseInsensitiveContains(q) ||
            $0.answer.localizedCaseInsensitiveContains(q)
        }
    }

    private var groupedItems: [HelpCategory: [HelpQAData.QAItem]] {
        Dictionary(grouping: filteredItems, by: { $0.category })
    }
}

// MARK: - HelpCategory display
private extension HelpCategory {

    var displayTitle: String {
        switch self {
        case .purchase:
            return "購入・権利確認"
        case .unlimited:
            return "Realtime"
        case .kit:
            return "Kit Check"
        case .scanStats:
            return "Scan Stats"
        case .troubleshooting:
            return "トラブルシューティング"
        }
    }
}
