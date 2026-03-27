import SwiftUI

private enum WorkDestination: Hashable {
    case realtime
    case kit
    case scanStats
    case purchase
}

struct WorkSelectionView: View {

    @State private var path = NavigationPath()
    @State private var showingMenuSheet: Bool = false

    @ObservedObject private var sessionManager = SessionManager.shared

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    if let suspended = sessionManager.suspendedSession, !suspended.isExpired {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("中断された作業")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Button {
                                let destination = destinationForSuspendedSession(suspended)
                                sessionManager.resumeSuspendedSession(suspended)
                                path.append(destination)
                            } label: {
                                WorkActionCard(
                                    title: "作業を再開",
                                    subtitle: resumeSubtitle(for: suspended),
                                    backgroundColor: Color.yellow.opacity(0.28)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("作業を選ぶ")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Button {
                            path.append(WorkDestination.realtime)
                        } label: {
                            WorkActionCard(
                                title: "Realtime Verification",
                                subtitle: "未購入でも1日1回だけ結果表示を体験できます",
                                backgroundColor: Color.blue.opacity(0.20)
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            path.append(WorkDestination.kit)
                        } label: {
                            WorkActionCard(
                                title: "Kit Check",
                                subtitle: "未購入でも最初の1回だけ結果表示を体験できます",
                                backgroundColor: Color.green.opacity(0.20)
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            path.append(WorkDestination.scanStats)
                        } label: {
                            WorkActionCard(
                                title: "Scan Stats",
                                subtitle: "未購入でも最初の5回だけ集計を体験できます",
                                backgroundColor: Color.orange.opacity(0.20)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("購入・課金")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Button {
                            path.append(WorkDestination.purchase)
                        } label: {
                            WorkActionCard(
                                title: "購入・課金（Purchase）",
                                subtitle: "プランの確認・購入・復元ができます",
                                backgroundColor: Color.purple.opacity(0.20)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("BoxVerify")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingMenuSheet = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("メニュー")
                }
            }
            .sheet(isPresented: $showingMenuSheet) {
                MenuSheet()
            }
            .navigationDestination(for: WorkDestination.self) { destination in
                switch destination {
                case .realtime:
                    RealtimeVerificationView()
                case .kit:
                    KitCheckView()
                case .scanStats:
                    ScanStatsView()
                case .purchase:
                    PurchaseView()
                }
            }
        }
    }

    private func resumeSubtitle(for session: SuspendedSession) -> String {
        switch session.payload {
        case .realtime:
            return "Realtime Verification を再開します"
        case .kit:
            return "Kit Check を再開します"
        case .scanStats:
            return "Scan Stats を再開します"
        }
    }

    private func destinationForSuspendedSession(_ session: SuspendedSession) -> WorkDestination {
        switch session.payload {
        case .realtime:
            return .realtime
        case .kit:
            return .kit
        case .scanStats:
            return .scanStats
        }
    }
}

private struct WorkActionCard: View {

    let title: String
    let subtitle: String
    let backgroundColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MenuSheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("設定・ヘルプ") {

                    NavigationLink("設定（Settings）") {
                        SettingsView()
                    }

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

                    NavigationLink("診断情報を見る") {
                        let text = DiagnosticsManager.exportText(
                            sessionManager: SessionManager.shared,
                            purchaseManager: PurchaseManager.shared
                        )

                        DiagnosticsView(diagnosticsText: text)
                    }
                }
            }
            .navigationTitle("メニュー")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}
