import SwiftUI

#if canImport(MessageUI)
import MessageUI

// MARK: - MailComposerView
struct MailComposerView: UIViewControllerRepresentable {

    let recipients: [String]
    let subject: String
    let body: String

    var onFinish: ((MFMailComposeResult) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // no-op
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {

        let parent: MailComposerView

        init(parent: MailComposerView) {
            self.parent = parent
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            // ✅ UIKit側を先に閉じる
            controller.dismiss(animated: true)

            // ✅ 結果通知（任意）
            parent.onFinish?(result)

            // ✅ SwiftUI sheet を閉じる
            parent.dismiss()
        }
    }
}

// MARK: - Capability helper
extension MailComposerView {
    static func canSendMail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }
}

#else

// MARK: - Fallback (MessageUIが無いビルド環境向け)
enum MFMailComposeResult: Int {
    case cancelled
    case saved
    case sent
    case failed
}

struct MailComposerView: View {

    let recipients: [String]
    let subject: String
    let body: String

    var onFinish: ((MFMailComposeResult) -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text("この環境ではメール送信が利用できません。")
                .font(.headline)
            Text("実機でお試しください。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

extension MailComposerView {
    static func canSendMail() -> Bool { false }
}

#endif
