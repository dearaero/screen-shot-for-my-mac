import AppKit
import Combine

final class ScreenshotManager {

    // MARK: - Singleton

    static let shared = ScreenshotManager()

    // MARK: - Properties

    private let monitor = ScreenshotMonitor()
    private let interceptor = HotkeyInterceptor()
    private let capture = ScreenshotCapture()
    /// Ordered array to preserve creation order (oldest first). Must only be accessed on main thread.
    private var activePanels: [ThumbnailPanel] = []
    /// Rotating index for rainbow mode color assignment
    private var rainbowColorIndex = 0
    /// Strong reference to keep the annotation editor window alive
    private var annotationEditor: AnnotationEditorWindow?

    // MARK: - Init

    private init() {
        monitor.onScreenshotDetected = { [weak self] url in
            self?.handleNewScreenshot(at: url)
        }

        interceptor.onScreenshotHotkey = { [weak self] mode in
            self?.handleScreenshotHotkey(mode: mode)
        }
    }

    // MARK: - Public

    func start() {
        monitor.start()
        interceptor.startIntercepting()
        NSLog("[ScreenshotManager] Started (monitor + interceptor)")
    }

    func stop() {
        interceptor.stopIntercepting()
        monitor.stop()
        dismissAllPanels()
        NSLog("[ScreenshotManager] Stopped")
    }

    /// Called by ScreenshotCapture after a file-based capture completes
    func handleCapturedScreenshot(at url: URL) {
        DispatchQueue.main.async { [weak self] in
            self?.handleNewScreenshot(at: url)
        }
    }

    /// Called by ScreenshotCapture when saveLocation is clipboardOnly
    func handleClipboardScreenshot(_ image: NSImage) {
        DispatchQueue.main.async { [weak self] in
            self?.handleNewClipboardScreenshot(image)
        }
    }

    // MARK: - Hotkey Handling

    private func handleScreenshotHotkey(mode: HotkeyInterceptor.ScreenshotMode) {
        guard !capture.isCapturing else {
            NSLog("[ScreenshotManager] Capture already in progress, ignoring hotkey: \(mode)")
            return
        }

        NSLog("[ScreenshotManager] Handling hotkey mode: \(mode)")

        switch mode {
        case .fullscreen:
            capture.captureFullscreen { [weak self] result in
                guard let result = result else { return }
                self?.handleCaptureResult(result)
            }

        case .areaSelection:
            capture.captureAreaSelection()

        case .windowSelection:
            capture.captureWindowSelection()

        case .screenshotApp:
            capture.openScreenshotApp()
        }
    }

    // MARK: - Menu Bar Actions

    func captureFullscreenFromMenu() {
        capture.captureFullscreen { [weak self] result in
            guard let result = result else { return }
            self?.handleCaptureResult(result)
        }
    }

    func captureAreaFromMenu() {
        capture.captureAreaSelection()
    }

    private func handleCaptureResult(_ result: ScreenshotCapture.CaptureResult) {
        switch result {
        case .savedToDisk(let url):
            handleNewScreenshot(at: url)
        case .clipboardOnly(let image):
            handleNewClipboardScreenshot(image)
        }
    }

    // MARK: - Screenshot Display (File-based)

    private func handleNewScreenshot(at url: URL) {
        NSLog("[ScreenshotManager] New screenshot: \(url.lastPathComponent)")

        guard let image = NSImage(contentsOf: url) else {
            NSLog("[ScreenshotManager] Failed to load image from: \(url.path)")
            return
        }

        showThumbnail(image: image, fileURL: url)
    }

    // MARK: - Screenshot Display (Clipboard-only)

    private func handleNewClipboardScreenshot(_ image: NSImage) {
        NSLog("[ScreenshotManager] New clipboard screenshot")
        showThumbnail(image: image, fileURL: nil)
    }

    // MARK: - Common Thumbnail Display

    private func showThumbnail(image: NSImage, fileURL: URL?) {
        assert(Thread.isMainThread, "showThumbnail must be called on main thread")

        let panel = ThumbnailPanel()

        panel.onDismiss = { [weak self] in
            self?.removePanel(panel)
        }

        panel.onEdit = { [weak self] image, url in
            NSLog("[ScreenshotManager] onEdit fired – image=\(image.size) url=\(url?.path ?? "nil")")
            self?.openAnnotationEditor(image: image, originalURL: url, panel: panel)
        }

        activePanels.append(panel)

        // Position using multi-column grid
        repositionAllPanels()

        panel.applyRainbowColor(at: rainbowColorIndex)
        rainbowColorIndex += 1

        if let fileURL = fileURL {
            panel.showScreenshot(at: fileURL)
        } else {
            panel.showScreenshotFromImage(image)
        }
    }

    private func removePanel(_ panel: ThumbnailPanel) {
        assert(Thread.isMainThread, "removePanel must be called on main thread")

        activePanels.removeAll { $0 === panel }
        panel.orderOut(nil)

        // Reposition remaining panels to close the gap
        repositionAllPanels()
    }

    // MARK: - Multi-Column Shingled Stack Layout

    private func repositionAllPanels() {
        assert(Thread.isMainThread, "repositionAllPanels must be called on main thread")

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let corner = SettingsStore.shared.thumbnailCorner

        let panelWidth: CGFloat = 240
        let panelHeight: CGFloat = 160
        let padding: CGFloat = 20
        let stackSpacing: CGFloat = 60
        let columnSpacing: CGFloat = 80

        let availableHeight = visibleFrame.height - padding * 2
        let panelsPerColumn = max(1, Int((availableHeight - panelHeight) / stackSpacing) + 1)

        var autoIndex = 0
        for panel in activePanels {
            guard !panel.isUserPositioned else { continue }

            let column = autoIndex / panelsPerColumn
            let row = autoIndex % panelsPerColumn
            let columnOffset = CGFloat(column) * (panelWidth + columnSpacing)
            let stackOffset = CGFloat(row) * stackSpacing

            let x: CGFloat
            let y: CGFloat

            switch corner {
            case .bottomLeft:
                x = visibleFrame.minX + padding + columnOffset
                y = visibleFrame.minY + padding + stackOffset
            case .bottomRight:
                x = visibleFrame.maxX - panelWidth - padding - columnOffset
                y = visibleFrame.minY + padding + stackOffset
            case .topLeft:
                x = visibleFrame.minX + padding + columnOffset
                y = visibleFrame.maxY - panelHeight - padding - stackOffset
            case .topRight:
                x = visibleFrame.maxX - panelWidth - padding - columnOffset
                y = visibleFrame.maxY - panelHeight - padding - stackOffset
            }

            panel.setFrameOrigin(NSPoint(x: x, y: y))
            autoIndex += 1
        }
    }

    private func dismissAllPanels() {
        for panel in activePanels {
            panel.orderOut(nil)
        }
        activePanels.removeAll()
    }

    // MARK: - Annotation Editor

    private func openAnnotationEditor(image: NSImage, originalURL: URL?, panel: ThumbnailPanel) {
        NSLog("[ScreenshotManager] openAnnotationEditor called")
        // Close any existing editor to prevent multiple overlapping windows
        annotationEditor?.close()
        annotationEditor = nil

        let editor = AnnotationEditorWindow(image: image, originalURL: originalURL) { [weak self] editedImage, url in
            self?.saveEditedImage(editedImage, originalURL: url, panel: panel)
            self?.annotationEditor = nil
        }
        annotationEditor = editor
        NSApplication.shared.activate(ignoringOtherApps: true)
        editor.orderFrontRegardless()
        editor.makeKey()
        NSLog("[ScreenshotManager] AnnotationEditorWindow ordered front")
    }

    private func saveEditedImage(_ image: NSImage, originalURL: URL?, panel: ThumbnailPanel) {
        guard let pngData = image.pngData() else {
            NSLog("[ScreenshotManager] Failed to generate PNG data for edited image")
            return
        }

        if let url = originalURL {
            // Overwrite original file
            do {
                try pngData.write(to: url)
                NSLog("[ScreenshotManager] Edited image saved to: \(url.path)")
                // Refresh thumbnail
                panel.showScreenshot(at: url)
            } catch {
                NSLog("[ScreenshotManager] Failed to overwrite edited image: \(error)")
            }
        } else {
            // Clipboard-only screenshot: save to default location
            let saveDir = SettingsStore.shared.outputDirectory
                ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Screenshots")
            try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let filename = "Screenshot \(formatter.string(from: Date())).png"
            let fileURL = saveDir.appendingPathComponent(filename)

            do {
                try pngData.write(to: fileURL)
                NSLog("[ScreenshotManager] Edited image saved to: \(fileURL.path)")
                panel.showScreenshot(at: fileURL)
            } catch {
                NSLog("[ScreenshotManager] Failed to save edited image: \(error)")
            }
        }
    }
}
