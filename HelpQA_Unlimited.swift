import Foundation

// MARK: - HelpQA_Unlimited
// HelpCategory.unlimited（Realtime 含む）
struct HelpQA_Unlimited {

    static let items: [HelpQAData.QAItem] = [

        .init(
            id: 1,
            category: .unlimited,
            question: "Q1. このアプリは常にオフラインで使うものですか？",
            answer: """
A. いいえ。
本アプリは「現場作業（スキャン・判定）はオフラインで完結できる」設計ですが、常にオフライン利用を前提としているわけではありません。

以下の操作はインターネット接続が必要です。
- 購入・課金（購入処理 / 価格取得）
- 購入状態の確認
- アプリのアップデート
- 問い合わせ（メール送信）

一度購入状態が確認されれば、現場でのスキャンや判定はオフラインでも利用できます。
"""
        ),

        .init(
            id: 2,
            category: .unlimited,
            question: "Q2. 無料で使える範囲はどこまでですか？（Realtime）",
            answer: """
A. 無料利用では、Realtime の合否判定（OK / NG表示）は「1日1回」まで利用できます。

無料状態でも次のことは可能です。
- コードの読み取り
- Base Code の登録

ただし、判定結果（OK / NG表示）は1日1回までです。
上限に達した日は、その日の判定結果を表示できません。

Realtime を購入すると、この制限はなくなり毎日制限なく利用できます。
"""
        ),

        .init(
            id: 3,
            category: .unlimited,
            question: "Q3. Base Code はどこで登録できますか？",
            answer: """
A. Base Code は Realtime 画面でコードをスキャンすると登録できます。

手入力で登録する場合は、メニュー内の「緊急手入力」から登録できます。

ただし無料利用でその日の上限（1日1回）に達している場合は、
緊急手入力でも登録・判定はできません。
"""
        ),

        .init(
            id: 4,
            category: .unlimited,
            question: "Q4. Base Code を削除したらどうなりますか？",
            answer: """
A. Base Code が設定されていない状態では照合はできません。

Realtime は「Base Code と完全一致するかどうか」で判定します。
そのため Base Code がない状態では照合処理は行われません。
"""
        ),

        .init(
            id: 5,
            category: .unlimited,
            question: "Q5. 判定が NG のとき、すぐにもう一度できますか？",
            answer: """
A. 無料利用の場合は、その日の判定上限（1日1回）を消費しているため
当日は再判定できません。

Realtime を購入すると、判定回数の制限はなくなります。
"""
        ),

        .init(
            id: 6,
            category: .unlimited,
            question: "Q6. 結果表示中にスキャンしても反応しません",
            answer: """
A. 仕様です。

結果表示中は、新しいスキャンは受け付けません。
表示を閉じた後に、次のスキャンを行ってください。
"""
        ),

        .init(
            id: 7,
            category: .unlimited,
            question: "Q7. 隣のバーコードを拾って NG になることがあります",
            answer: """
A. 複数のコードが同時にカメラに映ると、意図しないコードを読み取ることがあります。

次の方法をお試しください。
- 対象のコードをカメラ中央に入れる
- 周囲のコードが映り込まないようにする（紙などで隠す）
"""
        ),

        .init(
            id: 8,
            category: .unlimited,
            question: "Q8. 見た目は同じコードなのに一致しません",
            answer: """
A. コード内に空白や改行などの見えない文字が含まれている可能性があります。

診断情報では、改行などの不可視文字が含まれている場合でも
判別できる形式で表示されます。
"""
        ),

        .init(
            id: 9,
            category: .unlimited,
            question: "Q9. 無料の上限（1日1回）がリセットされるタイミングは？",
            answer: """
A. 日付が変わるとリセットされます。

本アプリの無料上限は Asia/Tokyo の日付を基準に管理されています。
"""
        ),

        .init(
            id: 10,
            category: .unlimited,
            question: "Q10. Realtime を購入するとどうなりますか？",
            answer: """
A. Realtime を購入すると、次の制限が解除されます。

- Realtime の合否判定（OK / NG）を毎日制限なく利用できます
- 無料の1日1回制限がなくなります

スキャン方法や操作方法は無料版と同じです。
"""
        ),
    ]
}
