import AppKit

final class ScreenshotCapture {

    // MARK: - Types

    enum CaptureResult {
        case savedToDisk(URL)
        case clipboardOnly(NSImage)
    }

    // MARK: - Properties

    private let captureQueue = DispatchQueue(label: "com.screenshoot.capture", qos: .userInitiated)
    private var currentOverlay: WindowCaptureOverlay?

    /// Thread-safe capture state. Always accessed via `captureQueue`.
    private var _isCapturing = false
    var isCapturing: Bool {
        captureQueue.sync { _isCapturing }
    }

    // MARK: - Capture (Fullscreen)

    func captureFullscreen(completion: ((CaptureResult?) -> Void)? = nil) {
        captureQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }
            guard !self._isCapturing else {
                NSLog("[ScreenshotCapture] Already capturing, ignoring fullscreen")
                DispatchQueue.main.async { completion?(nil) }
                return
            }
            self._isCapturing = true
            defer { self._isCapturing = false }

            let settings = SettingsStore.shared
            let result: CaptureResult?
            if settings.saveLocation == .clipboardOnly {
                result = self.runCaptureToClipboard(arguments: [])
            } else if let directory = settings.outputDirectory {
                let fileURL = self.generateScreenshotURL(in: directory)
                result = self.runCapture(arguments: [fileURL.path], expectedFile: fileURL)
            } else {
                result = nil
            }

            if let result = result {
                self.notifyManager(result: result)
            }
            DispatchQueue.main.async { completion?(result) }
        }
    }

    // MARK: - Capture (Area Selection)

    func captureAreaSelection() {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self._isCapturing else {
                NSLog("[ScreenshotCapture] Already capturing, ignoring area selection")
                return
            }
            self._isCapturing = true
            defer { self._isCapturing = false }

            let settings = SettingsStore.shared
            let saveLocation = settings.saveLocation
            let directory = settings.outputDirectory
            let fileURL = directory.map { self.generateScreenshotURL(in: $0) }

            // Always use temp file for interactive captures to reliably detect cancellation
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".png")
            defer {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }

            guard self.runCapture(arguments: ["-i", tempURL.path], expectedFile: tempURL) != nil else {
                NSLog("[ScreenshotCapture] Area selection cancelled or failed")
                return
            }

            if saveLocation == .clipboardOnly {
                guard let image = NSImage(contentsOf: tempURL) else { return }
                self.copyImageToClipboard(image)
                self.notifyManager(result: .clipboardOnly(image))
            } else if let url = fileURL {
                do {
                    try FileManager.default.moveItem(at: tempURL, to: url)
                    self.notifyManager(result: .savedToDisk(url))
                } catch {
                    NSLog("[ScreenshotCapture] Failed to move temp file: \(error)")
                }
            }
        }
    }

    // MARK: - Capture (Window Selection)

    func captureWindowSelection() {
        guard !isCapturing else {
            NSLog("[ScreenshotCapture] Already capturing, ignoring window selection")
            return
        }

        let settings = SettingsStore.shared
        let saveLocation = settings.saveLocation
        let directory = settings.outputDirectory
        let fileURL = directory.map { generateScreenshotURL(in: $0) }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                self?.captureQueue.async { [weak self] in self?._isCapturing = false }
                return
            }

            let overlay = WindowCaptureOverlay()
            self.currentOverlay = overlay

            overlay.show(
                onCapture: { [weak self] windowID in
                    guard let self = self else { return }
                    self.currentOverlay = nil

                    self.captureQueue.async {
                        defer { self._isCapturing = false }

                        if saveLocation == .clipboardOnly {
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString + ".png")
                            defer {
                                if FileManager.default.fileExists(atPath: tempURL.path) {
                                    try? FileManager.default.removeItem(at: tempURL)
                                }
                            }
                            guard self.runCapture(arguments: ["-l\(windowID)", tempURL.path], expectedFile: tempURL) != nil else { return }
                            guard let image = NSImage(contentsOf: tempURL) else { return }
                            self.copyImageToClipboard(image)
                            self.notifyManager(result: .clipboardOnly(image))
                            return
                        }

                        guard let url = fileURL else { return }
                        if let result = self.runCapture(arguments: ["-l\(windowID)", url.path], expectedFile: url) {
                            self.notifyManager(result: result)
                        }
                    }
                },
                onCancel: { [weak self] in
                    NSLog("[ScreenshotCapture] Window capture cancelled by user")
                    self?.currentOverlay = nil
                    self?.captureQueue.async { [weak self] in self?._isCapturing = false }
                }
            )
        }
    }

    // MARK: - Capture (Screenshot App)

    func openScreenshotApp() {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self._isCapturing else {
                NSLog("[ScreenshotCapture] Already capturing, ignoring screenshot app")
                return
            }
            self._isCapturing = true
            defer { self._isCapturing = false }

            let settings = SettingsStore.shared
            let saveLocation = settings.saveLocation
            let directory = settings.outputDirectory
            let fileURL = directory.map { self.generateScreenshotURL(in: $0) }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".png")
            defer {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }

            guard self.runCapture(arguments: ["-i", tempURL.path], expectedFile: tempURL) != nil else {
                NSLog("[ScreenshotCapture] Screenshot app capture cancelled or failed")
                return
            }

            if saveLocation == .clipboardOnly {
                guard let image = NSImage(contentsOf: tempURL) else { return }
                self.copyImageToClipboard(image)
                self.notifyManager(result: .clipboardOnly(image))
            } else if let url = fileURL {
                do {
                    try FileManager.default.moveItem(at: tempURL, to: url)
                    self.notifyManager(result: .savedToDisk(url))
                } catch {
                    NSLog("[ScreenshotCapture] Failed to move temp file: \(error)")
                }
            }
        }
    }

    // MARK: - Core Capture (runs on captureQueue)

    private func runCapture(arguments: [String], expectedFile: URL) -> CaptureResult? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = arguments

        do {
            try task.run()

            // Wait with a generous timeout to prevent indefinite hangs
            let semaphore = DispatchSemaphore(value: 0)
            var terminated = false
            task.terminationHandler = { _ in
                terminated = true
                semaphore.signal()
            }
            let waitResult = semaphore.wait(timeout: .now() + 60)
            if waitResult == .timedOut {
                NSLog("[ScreenshotCapture] screencapture timed out, terminating")
                task.terminate()
                return nil
            }

            if task.terminationStatus == 0 && FileManager.default.fileExists(atPath: expectedFile.path) {
                NSLog("[ScreenshotCapture] Saved: \(expectedFile.lastPathComponent)")
                return .savedToDisk(expectedFile)
            }
        } catch {
            NSLog("[ScreenshotCapture] Capture failed: \(error)")
        }

        return nil
    }

    // MARK: - Clipboard-Only Capture

    private func runCaptureToClipboard(arguments: [String]) -> CaptureResult? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = arguments + ["-c"]

        do {
            try task.run()
            task.waitUntilExit()

            guard task.terminationStatus == 0 else {
                NSLog("[ScreenshotCapture] Clipboard capture cancelled or failed")
                return nil
            }

            // Read image from clipboard (must read on main thread for NSPasteboard)
            var image: NSImage?
            if Thread.isMainThread {
                image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
            } else {
                DispatchQueue.main.sync {
                    image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
                }
            }

            guard let image = image else {
                NSLog("[ScreenshotCapture] Failed to read image from clipboard")
                return nil
            }

            NSLog("[ScreenshotCapture] Captured to clipboard")
            return .clipboardOnly(image)
        } catch {
            NSLog("[ScreenshotCapture] Clipboard capture failed: \(error)")
            return nil
        }
    }

    // MARK: - Clipboard Helper

    private func copyImageToClipboard(_ image: NSImage) {
        let writeBlock = {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
        if Thread.isMainThread {
            writeBlock()
        } else {
            DispatchQueue.main.sync(execute: writeBlock)
        }
    }

    // MARK: - Notify Manager (always on main thread)

    private func notifyManager(result: CaptureResult) {
        DispatchQueue.main.async {
            switch result {
            case .savedToDisk(let url):
                ScreenshotManager.shared.handleCapturedScreenshot(at: url)
            case .clipboardOnly(let image):
                ScreenshotManager.shared.handleClipboardScreenshot(image)
            }
        }
    }

    // MARK: - File Naming

    private static let screenshotDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    private func generateScreenshotURL(in directory: URL) -> URL {
        let timestamp = Self.screenshotDateFormatter.string(from: Date())
        let filename = "Screenshot \(timestamp).png"

        var fileURL = directory.appendingPathComponent(filename)

        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            let altFilename = "Screenshot \(timestamp) \(counter).png"
            fileURL = directory.appendingPathComponent(altFilename)
            counter += 1
        }

        return fileURL
    }
}
