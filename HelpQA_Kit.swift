import Foundation

// MARK: - HelpQA_Kit
struct HelpQA_Kit {

    static let items: [HelpQAData.QAItem] = [

        .init(
            id: 20,
            category: .kit,
            question: "Q20. Kit Check の Kit ID は判定対象ですか？",
            answer: """
A. いいえ。
Kit ID は「どのキット定義を使うか」を選ぶためのコードです。

Kit Check では次の流れで動作します。

1. Kit ID を読み取り
2. 対応する Kit 定義を読み込み
3. 構成品コードをスキャンして判定

判定対象になるのは構成品コードです。
"""
        ),

        .init(
            id: 21,
            category: .kit,
            question: "Q21. Kit ID を間違えて読んだ場合はどうすればいいですか？",
            answer: """
A. 作業を終了して、正しい Kit ID で最初からやり直してください。

Kit ID は作業開始時に確定するため、途中で変更することはできません。
"""
        ),

        .init(
            id: 22,
            category: .kit,
            question: "Q22. Kit Check を中断すると、再開時はどこまで残りますか？",
            answer: """
A. 次の情報が保存されます。

- Kit ID
- 必要数量
- 現在のスキャン進捗

中断データは最大1件だけ保存されます。
また、一定期間（7日）を過ぎると自動削除されます。
削除された場合は復元できません。
"""
        ),

        .init(
            id: 23,
            category: .kit,
            question: "Q23. Kit Check で数量を超えてスキャンしたら？",
            answer: """
A. 有料利用中は completedNG（数量超過）になります。

未購入でも内部進行は行われますが、通常は次の表示は行われません。

- 進捗表示
- 不足内訳表示
- 継続的な結果表示

ただし、最初に発生した completedOK / completedNG の結果だけ
1回だけ表示して体験できます。

その1回を使い切った後は、結果表示は行われずトーストのみになります。
"""
        ),

        .init(
            id: 24,
            category: .kit,
            question: "Q24. 未購入でも Kit Check は使えますか？",
            answer: """
A. はい。未購入でもスキャン自体はできます。

また、次の内部処理は行われます。

- Kit ID の選択
- 構成品スキャン
- 必要数量との照合

ただし未購入では次の制限があります。

- 進捗表示は行われません
- 不足内訳表示は行われません
- 継続的な結果表示は行われません
- 作業進捗として使う前提ではありません

なお、最初に発生した completedOK / completedNG の結果だけ
1回だけ表示して体験できます。
その後は結果表示は行われずトーストのみになります。
"""
        ),

        .init(
            id: 25,
            category: .kit,
            question: "Q25. Kit の登録・編集はどこからできますか？",
            answer: """
A. 設定（Settings）の Kit 管理画面から登録・編集できます。

Kit ID（キット識別コード）と、
構成品コード・必要数量を登録してください。
"""
        ),

        .init(
            id: 26,
            category: .kit,
            question: "Q26. Kit の登録数や構成品数に上限はありますか？",
            answer: """
A. 構成品には上限があります。

- 1 Kit あたり構成品：最大 5 項目
- 1 構成品あたり必要数量：最大 30

※数量上限はアプリの仕様として固定されています。
"""
        ),

        .init(
            id: 27,
            category: .kit,
            question: "Q27. Kit Check で同じコードをもう一度カウントしたい",
            answer: """
A. Kit Check は手動確定方式です。

コード候補が表示された状態で、中央の丸ボタンを押すと確定されます。
そのため、同じコードが画面に残っていても、ボタンを押すたびに再カウントできます。

ただし次の場合は確定できません。

- 必要数量を超えている場合（有料利用時は completedNG）
- 複数のコードが同時に映っている場合（候補が出ません）

確実に使うには、枠内に1つのコードだけを表示してください。
"""
        ),
    ]
}
