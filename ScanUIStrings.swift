import Foundation

enum ScanUIStrings {

    static let scanPleaseTitle = "コードをスキャンしてください"
    static let qrViewfinderSF = "qrcode.viewfinder"
    static let confirmHint = "候補が出たら中央の丸ボタンで確定してください。"

    enum Realtime {
        static let screenTitle = "Realtime Verify"
        static let screenSubtitle = "完全一致判定"

        static let baseCodeTitle = "Base Code をスキャンしてください"
        static let baseCodeMessage = "最初の1回は基準コード（Base Code）です。登録後、次のスキャンで照合します。"

        static let verifyTitle = "コードをスキャンしてください"
        static let verifyMessage = "Base Code と完全一致で判定します。"

        static let trialExhaustedTitle = "本日の無料利用は終了しました"
        static let trialExhaustedMessage = "無料で判定結果を表示できるのは1日1回までです。続けるには Realtime の購入が必要です。"
        static let trialExhaustedToast = "本日の無料利用は終了しました（Realtimeの購入が必要）"

        static let baseRegisteredTitle = "Base Code 登録完了"
        static let baseRegisteredMessage = "次は照合したいコードをスキャンしてください。"

        static let cannotRegisterTitle = "登録できません"
        static let cannotRegisterMessage = "改行・タブなどの制御文字が含まれている可能性があります。"

        static let baseMissingTitle = "Base Code 未登録"
        static let baseMissingMessage = "Base Code をスキャンして登録してください。"

        static let okTitle = "OK"
        static let ngTitle = "NG"
        static let okMessage = "一致しました"
        static let ngMessage = "一致しません"
    }

    enum ScanStats {
        static let screenTitle = "Scan Stats"
        static let screenSubtitle = "コード種別別カウント"

        static let paidCardMessage = "スキャンしたコードを種類別にカウントします。"
        static let unpaidCardMessage = "Scan Stats は有料プランです。無課金でも最初の5回だけ集計を体験でき、その後は結果表示にプランが必要です。"

        // ✅ 体験中（1〜5回目）
        static let unpaidToast = "読み取りました（最初の5回まで集計を体験できます）"

        // ✅ 6回目以降
        static let unpaidLockedToast = "読み取りました（集計表示はScan Stats有料プラン）"

        // ✅ 体験仕様の案内
        static let trialLimitMessage = "この結果表示は5回までの体験です。6回目以降の集計表示には Scan Stats プランが必要です。"

        static let limitTitle = "上限に到達"
        static let maxTypesMessage = "種類数が上限（10種類）に達しました。Resetで新しい作業として再開できます。"
        static let maxTotalMessage = "トータルが上限（1,000回）に達しました。Resetで新しい作業として再開できます。"

        static let noSessionTitle = "未開始"
        static let noSessionMessage = "セッションが開始されていません。画面を開き直すか、Resetで新規作業として開始してください。"
    }

    enum Kit {
        static let screenTitle = "Kit Check"
        static let screenSubtitle = "キットセット確認"

        static let unpaidTitle = "Kit Check は有料プランです"
        static let unpaidMessage = "無課金でもスキャンはできます。最初の1回だけ結果表示を体験でき、その後は結果表示にKitプランが必要です。"
        static let unpaidToast = "読み取りました（結果表示はKit有料プラン）"
        static let unpaidKitIdToast = "Kit ID を読み取りました（最初の1回だけ結果表示を体験できます）"

        static let needKitIdTitle = "Kit ID をスキャンしてください"
        static let needKitIdMessage = "最初の1回は『キット識別コード（Kit ID）』です。"

        static let cannotStartTitle = "Kit Check を開始できません"
        static let cannotStartMessage = "画面を開き直してください。"

        static let okTitle = "OK"
        static let okMessage = "必要数が揃いました。"

        static let notJudgedTitle = "未判定"
        static let noSessionMessage = "セッションがありません。"

        static let trialResultSuffix = "（この結果表示は1回限りの体験です。次回以降はKitプランが必要です）"
    }
}
