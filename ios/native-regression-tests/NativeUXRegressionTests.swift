import XCTest
import UIKit
import QuickLook
import AppIntents

@MainActor
final class NativeUXRegressionTests: XCTestCase {
    func testNavigationIntentsEnqueueTheTwoDiscoverableForegroundActions() async throws {
        XCTAssertTrue(ResumeLastChatIntent.openAppWhenRun)
        XCTAssertTrue(OpenFavoritesIntent.openAppWhenRun)
        XCTAssertEqual(LumiverseAppShortcuts.appShortcuts.count, 2)
        _ = try await ResumeLastChatIntent().perform()
        XCTAssertEqual(NavigationShortcutInbox.pending()?.action, .resumeChat)
        _ = try await OpenFavoritesIntent().perform()
        let pending = try XCTUnwrap(NavigationShortcutInbox.pending())
        XCTAssertEqual(pending.action, .favorites)
        XCTAssertTrue(NavigationShortcutInbox.acknowledge(pending.id.uuidString))
        XCTAssertNil(NavigationShortcutInbox.pending())
    }

    func testSavedPDFOffersPreviewAndShareAndQuickLookReceivesTheLocalFile() async throws {
        let (window, controller, view) = makeWindow()
        defer { window.isHidden = true }
        let presenter = NativeExportPresenter(view: view)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).writePDF(to: file) { context in
            context.beginPage()
            "Lumiverse export".draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        presenter.showResult(filename: file.lastPathComponent, success: true, fileURL: file)
        let alert = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.actions.compactMap(\.title), ["Preview", "Share…", "OK"])
        await dismiss(controller)
        XCTAssertNil(controller.presentedViewController, "The alert must finish dismissing before preview")
        XCTAssertNotNil(view.window, "The export view must remain attached")
        XCTAssertTrue(view.window?.rootViewController === controller)
        presenter.preview(file)
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            controller.presentedViewController is QLPreviewController
        }, object: nil)], timeout: 5)
        let preview = try XCTUnwrap(controller.presentedViewController as? QLPreviewController)
        let source = try XCTUnwrap(preview.dataSource)
        XCTAssertEqual(source.numberOfPreviewItems(in: preview), 1)
        XCTAssertEqual(source.previewController(preview, previewItemAt: 0).previewItemURL, file)
        await dismiss(controller)
        XCTAssertNil(controller.presentedViewController, "The alert must finish dismissing before sharing")
        XCTAssertNotNil(view.window, "The export view must remain attached")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Preview must retain the saved export")
    }

    func testFailedExportOffersNoFileActionsAndSharingHasAnIPadPopoverAnchor() async throws {
        let (window, controller, view) = makeWindow()
        defer { window.isHidden = true }
        let presenter = NativeExportPresenter(view: view)
        presenter.showResult(filename: "failed.json", success: false)
        let alert = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.title, "Export failed")
        XCTAssertEqual(alert.actions.compactMap(\.title), ["OK"])
        await dismiss(controller)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("{\"export\":true}".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        presenter.share(file)
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            controller.presentedViewController is UIActivityViewController
        }, object: nil)], timeout: 5)
        let sheet = try XCTUnwrap(controller.presentedViewController as? UIActivityViewController)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(sheet.popoverPresentationController?.sourceView === controller.view)
            XCTAssertEqual(sheet.popoverPresentationController?.sourceRect.size, CGSize(width: 1, height: 1))
        }
        await dismiss(controller)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Sharing must retain the saved export")
    }

    private func makeWindow() -> (UIWindow, UIViewController, UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 768, height: 1024))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let view = UIView(frame: controller.view.bounds)
        controller.view.addSubview(view)
        return (window, controller, view)
    }

    private func dismiss(_ controller: UIViewController) async {
        // Wait for the presentation transition before asking UIKit to dismiss.
        try? await Task.sleep(nanoseconds: 400_000_000)
        await withCheckedContinuation { continuation in
            controller.dismiss(animated: false) { continuation.resume() }
        }
    }
}
