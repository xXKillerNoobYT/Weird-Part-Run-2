import SwiftUI
import MessageUI

// MARK: - MFMailComposeViewController wrapper

/// Wraps MFMailComposeViewController so SwiftUI can present it as a sheet.
struct MailComposerSheet: UIViewControllerRepresentable {

    let to: [String]
    let subject: String
    let body: String
    let attachments: [(data: Data, mimeType: String, fileName: String)]
    var onFinished: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(to)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        for att in attachments {
            vc.addAttachmentData(att.data, mimeType: att.mimeType, fileName: att.fileName)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerSheet
        init(_ parent: MailComposerSheet) { self.parent = parent }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            parent.onFinished(result)
        }
    }
}

// MARK: - Availability helper

extension MFMailComposeViewController {
    static var isAvailableOnDevice: Bool { canSendMail() }
}
