import UIKit
import QuickLook

/// Presentation is separate from download/cookie handling so exports always
/// share the finished local file, including on iPads that require popover anchors.
final class NativeExportPresenter: NSObject, QLPreviewControllerDataSource {
    private weak var view: UIView?
    private var previewURL: URL?

    init(view: UIView) { self.view = view }

    func showResult(filename: String, success: Bool, fileURL: URL? = nil) {
        guard let controller = view?.window?.rootViewController, controller.presentedViewController == nil else { return }
        let deviceFolder = UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone"
        let alert = UIAlertController(title: success ? "Export saved" : "Export failed",
            message: success ? "\(filename)\nFiles → \(deviceFolder) → Lumiverse" : "Could not save \(filename). Check your connection and available storage, then try again.",
            preferredStyle: .alert)
        if let fileURL = fileURL, success {
            if QLPreviewController.canPreview(fileURL as NSURL) {
                alert.addAction(UIAlertAction(title: "Preview", style: .default) { [weak self, weak alert] _ in
                    alert?.dismiss(animated: true) { [weak self] in self?.preview(fileURL) }
                })
            }
            alert.addAction(UIAlertAction(title: "Share…", style: .default) { [weak self, weak alert] _ in
                alert?.dismiss(animated: true) { [weak self] in self?.share(fileURL) }
            })
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        controller.present(alert, animated: true)
    }

    func preview(_ url: URL) {
        guard let controller = view?.window?.rootViewController, controller.presentedViewController == nil else { return }
        previewURL = url
        let preview = QLPreviewController()
        preview.dataSource = self
        controller.present(preview, animated: true)
    }

    func share(_ url: URL) {
        guard let controller = view?.window?.rootViewController, controller.presentedViewController == nil else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = controller.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX,
            y: controller.view.bounds.midY, width: 1, height: 1)
        controller.present(sheet, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        previewURL! as NSURL
    }
}
