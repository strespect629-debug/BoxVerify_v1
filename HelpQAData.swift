import Foundation

// MARK: - HelpQAData (SSOT)
// ✅ カテゴリ別ファイルを結合して items を提供する「唯一の参照口」
// ✅ HelpView は HelpQAData.items のみ参照する
// ✅ Q番号(id)は固定（Q1〜Q60）
// ✅ QAItem を HelpView 側で再定義しない（重複定義＝事故原因）

struct HelpQAData {

    struct QAItem: Identifiable {
        let id: Int
        let category: HelpCategory
        let question: String
        let answer: String
    }

    static let items: [QAItem] =
        HelpQA_Unlimited.items
        + HelpQA_Purchase.items
        + HelpQA_Kit.items
        + HelpQA_ScanStats.items
        + HelpQA_Troubleshooting.items
}
