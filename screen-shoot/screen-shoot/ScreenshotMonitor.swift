import Foundation
import AppKit

final class ScreenshotMonitor {

    // MARK: - Types

    enum ScreenshotLocation {
        case desktop
        case custom(URL)

        var url: URL {
            switch self {
            case .desktop:
                return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            case .custom(let url):
                return url
            }
        }
    }

    // MARK: - Properties

    private var eventSource: DispatchSourceFileSystemObject?
    private let monitoredLocation: ScreenshotLocation
    private let queue = DispatchQueue(label: "com.screenshoot.monitor", qos: .utility)
    private var knownFiles: Set<String> = []
    private let debounceInterval: TimeInterval = 0.3
    private var debounceWorkItem: DispatchWorkItem?

    var onScreenshotDetected: ((URL) -> Void)?

    private static let screenshotPatterns: [NSRegularExpression] = {
        let patterns = [
            #"Screenshot \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}"#,
            #"Ekran Resmi \d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.\d{2}"#,
            #"Screen Shot \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "bmp", "gif", "heic"]

    // MARK: - Init

    init(location: ScreenshotLocation = .desktop) {
        self.monitoredLocation = location
    }

    deinit {
        stop()
    }

    // MARK: - Public

    func start() {
        queue.async { [weak self] in
            self?.scanExistingFiles()
            self?.beginMonitoring()
        }
    }

    func stop() {
        eventSource?.cancel()
        eventSource = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    // MARK: - Private

    private func scanExistingFiles() {
        let fm = FileManager.default
        let directoryURL = monitoredLocation.url

        guard let contents = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        for fileURL in contents {
            knownFiles.insert(fileURL.lastPathComponent)
        }
    }

    private func beginMonitoring() {
        let directoryURL = monitoredLocation.url
        let directoryPath = directoryURL.path

        let descriptor = open(directoryPath, O_EVTONLY)
        guard descriptor >= 0 else {
            NSLog("[ScreenshotMonitor] Failed to open directory: \(directoryPath)")
            return
        }
        // Ensure descriptor is closed even if source creation fails
        defer {
            if eventSource == nil {
                close(descriptor)
            }
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.handleFileSystemEvent()
        }

        source.setCancelHandler {
            close(descriptor)
        }

        self.eventSource = source
        source.resume()
    }

    private func handleFileSystemEvent() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.processNewFiles()
        }
        self.debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func processNewFiles() {
        let fm = FileManager.default
        let directoryURL = monitoredLocation.url

        guard let contents = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let currentFiles = Set(contents.map { $0.lastPathComponent })
        let newFiles = currentFiles.subtracting(knownFiles)

        for filename in newFiles {
            let fileURL = directoryURL.appendingPathComponent(filename)

            guard isScreenshotFile(url: fileURL) else { continue }

            // Wait briefly for file to finish writing (with safety cap)
            guard waitForFileStability(url: fileURL) else { continue }

            NSLog("[ScreenshotMonitor] Detected screenshot: \(fileURL.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                self?.onScreenshotDetected?(fileURL)
            }
        }

        knownFiles = currentFiles
    }

    private func isScreenshotFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard Self.imageExtensions.contains(ext) else { return false }

        let filename = url.deletingPathExtension().lastPathComponent
        let matchesPattern = Self.screenshotPatterns.contains { pattern in
            let range = NSRange(filename.startIndex..., in: filename)
            return pattern.firstMatch(in: filename, range: range) != nil
        }

        return matchesPattern
    }

    /// Waits for the file size to stabilize. Returns false if the file never stabilizes.
    private func waitForFileStability(url: URL) -> Bool {
        let fm = FileManager.default
        var prevSize: UInt64 = 0
        var stableCount = 0
        let maxIterations = 30 // 30 * 50ms = 1.5s max wait

        for _ in 0..<maxIterations {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? UInt64 else {
                usleep(100_000)
                continue
            }

            if size == prevSize && size > 0 {
                stableCount += 1
                if stableCount >= 3 {
                    return true
                }
            } else {
                stableCount = 0
                prevSize = size
            }
            usleep(50_000)
        }

        NSLog("[ScreenshotMonitor] File did not stabilize: \(url.lastPathComponent)")
        return false
    }
}
