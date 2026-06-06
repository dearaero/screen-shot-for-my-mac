import AppKit

// MARK: - Draggable Handle View

final class DraggableHandleView: NSView {

    weak var panel: ThumbnailPanel?
    private var dragStartScreenPoint: NSPoint?
    private var dragStartOrigin: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard let panel = panel else { return }
        dragStartScreenPoint = NSEvent.mouseLocation
        dragStartOrigin = panel.frame.origin
        NSCursor.closedHand.set()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0.95
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel = panel,
              let startScreenPoint = dragStartScreenPoint,
              let startOrigin = dragStartOrigin else { return }

        let currentScreenPoint = NSEvent.mouseLocation
        var newX = startOrigin.x + currentScreenPoint.x - startScreenPoint.x
        var newY = startOrigin.y + currentScreenPoint.y - startScreenPoint.y

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            let panelSize = panel.frame.size
            newX = max(visibleFrame.minX, min(newX, visibleFrame.maxX - panelSize.width))
            newY = max(visibleFrame.minY, min(newY, visibleFrame.maxY - panelSize.height))
        }

        panel.setFrameOrigin(NSPoint(x: newX, y: newY))
    }

    override func mouseUp(with event: NSEvent) {
        guard let panel = panel else {
            NSCursor.arrow.set()
            return
        }
        panel.isUserPositioned = true
        dragStartScreenPoint = nil
        dragStartOrigin = nil
        NSCursor.arrow.set()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1.0
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

// MARK: - Thumbnail Panel

final class ThumbnailPanel: NSPanel {

    // MARK: - Constants

    private enum Layout {
        static let thumbnailWidth: CGFloat = 240
        static let thumbnailHeight: CGFloat = 160
        static let cornerRadius: CGFloat = 12
        static let animationDuration: TimeInterval = 0.35
    }

    // MARK: - Properties

    private var screenshotURL: URL?
    private var screenshotImage: NSImage?
    private var thumbnailImageView: NSImageView?
    private var dragStartPoint: NSPoint?
    private var isDraggingContent = false
    private var dismissTimer: Timer?
    private var lastDragTempURL: URL?
    private var clipboardTempURL: URL?

    private var hasFileOnDisk: Bool { screenshotURL != nil }
    var isUserPositioned = false
    var onDismiss: (() -> Void)?
    var onEdit: ((NSImage, URL?) -> Void)?

    // MARK: - Init

    deinit {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let tempURL = lastDragTempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        if let tempURL = clipboardTempURL {
            try? FileManager.default.removeItem(at: tempURL)
            clipboardTempURL = nil
        }
        // Clean up feedback labels that may still be animating
        contentView?.subviews.forEach { subview in
            subview.layer?.removeAllAnimations()
            subview.removeFromSuperview()
        }
    }

    init() {
        super.init(
            contentRect: NSRect(
                x: 20, y: 20,
                width: Layout.thumbnailWidth,
                height: Layout.thumbnailHeight
            ),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        setupContentView()
        cleanStaleDragTempFiles()
    }

    // MARK: - Panel Configuration

    private func configurePanel() {
        level = .floating
        isFloatingPanel = true
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        ignoresMouseEvents = false
    }

    // MARK: - Content Setup

    private func setupContentView() {
        let container = NSView(frame: NSRect(
            x: 0, y: 0,
            width: Layout.thumbnailWidth,
            height: Layout.thumbnailHeight
        ))
        container.wantsLayer = true
        container.layer?.cornerRadius = Layout.cornerRadius
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.borderWidth = 0

        let imageView = NSImageView(frame: container.bounds.insetBy(dx: 6, dy: 6))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = Layout.cornerRadius - 3
        imageView.layer?.masksToBounds = true
        self.thumbnailImageView = imageView
        container.addSubview(imageView)

        let moveHandle = DraggableHandleView(frame: NSRect(x: Layout.thumbnailWidth - 50, y: Layout.thumbnailHeight - 28, width: 22, height: 22))
        moveHandle.panel = self

        let moveImageView = NSImageView(frame: moveHandle.bounds)
        moveImageView.image = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right", accessibilityDescription: "Move")
        moveImageView.imageScaling = .scaleProportionallyUpOrDown
        moveImageView.contentTintColor = .secondaryLabelColor
        moveHandle.addSubview(moveImageView)
        container.addSubview(moveHandle)

        let closeButton = NSButton(frame: NSRect(x: Layout.thumbnailWidth - 28, y: Layout.thumbnailHeight - 28, width: 22, height: 22))
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 11
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(dismissPanel)
        container.addSubview(closeButton)

        let dragLabel = NSTextField(labelWithString: "Drag to share")
        dragLabel.font = .systemFont(ofSize: 10, weight: .medium)
        dragLabel.textColor = .tertiaryLabelColor
        dragLabel.frame = NSRect(
            x: (Layout.thumbnailWidth - dragLabel.intrinsicContentSize.width) / 2,
            y: 8,
            width: dragLabel.intrinsicContentSize.width,
            height: dragLabel.intrinsicContentSize.height
        )
        container.addSubview(dragLabel)

        contentView = container
    }

    // MARK: - Display Screenshot

    func showScreenshot(at url: URL) {
        self.screenshotURL = url

        guard let image = NSImage(contentsOf: url) else {
            NSLog("[ThumbnailPanel] Failed to load image from: \(url.path)")
            return
        }

        self.screenshotImage = image
        displayImage(image)
    }

    func showScreenshotFromImage(_ image: NSImage) {
        self.screenshotImage = image
        displayImage(image)
    }

    private func displayImage(_ image: NSImage) {
        thumbnailImageView?.image = image

        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }

        resetDismissTimer()
    }

    // MARK: - Rainbow Mode

    static let rainbowColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemBlue, .systemPurple, .systemPink
    ]

    func applyRainbowColor(at index: Int) {
        guard SettingsStore.shared.isRainbowMode else { return }
        let color = Self.rainbowColors[index % Self.rainbowColors.count]
        contentView?.layer?.borderWidth = 4
        contentView?.layer?.borderColor = color.cgColor
    }

    // MARK: - Positioning

    func positionAtCorner(_ corner: ThumbnailCorner, offset: CGFloat = 0) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let padding: CGFloat = 20

        let x: CGFloat
        let y: CGFloat

        switch corner {
        case .bottomLeft:
            x = visibleFrame.minX + padding
            y = visibleFrame.minY + padding + offset
        case .bottomRight:
            x = visibleFrame.maxX - Layout.thumbnailWidth - padding
            y = visibleFrame.minY + padding + offset
        case .topLeft:
            x = visibleFrame.minX + padding
            y = visibleFrame.maxY - Layout.thumbnailHeight - padding - offset
        case .topRight:
            x = visibleFrame.maxX - Layout.thumbnailWidth - padding
            y = visibleFrame.maxY - Layout.thumbnailHeight - padding - offset
        }

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Dismiss

    @objc private func dismissPanel() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if let tempURL = lastDragTempURL {
            try? FileManager.default.removeItem(at: tempURL)
            lastDragTempURL = nil
        }
        if let tempURL = clipboardTempURL {
            try? FileManager.default.removeItem(at: tempURL)
            clipboardTempURL = nil
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Layout.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.onDismiss?()
        })
    }

    private func resetDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: 300,
            repeats: false
        ) { [weak self] _ in
            self?.dismissPanel()
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = event.locationInWindow
        isDraggingContent = false
        resetDismissTimer()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = dragStartPoint else { return }

        let currentPoint = event.locationInWindow
        let dx = currentPoint.x - startPoint.x
        let dy = currentPoint.y - startPoint.y

        if !isDraggingContent && hypot(dx, dy) > 5 {
            isDraggingContent = true
            beginDragSession(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !isDraggingContent {
            if hasFileOnDisk {
                openInFinder()
            } else {
                copyToClipboard()
            }
        }

        dragStartPoint = nil
        isDraggingContent = false
    }

    // MARK: - Drag Session

    private func beginDragSession(with event: NSEvent) {
        guard let image = screenshotImage else { return }

        let dragURL: URL
        if let url = screenshotURL {
            dragURL = url
        } else {
            guard let tempURL = writeImageToTemporaryFile(image) else { return }
            dragURL = tempURL
            lastDragTempURL = tempURL
        }

        let writer = dragURL as NSURL
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)

        let dragImageSize = NSSize(width: 200, height: 133)
        let dragImage = image.resized(to: dragImageSize)

        let mouseLoc = NSEvent.mouseLocation
        let dragFrame = NSRect(
            x: mouseLoc.x - dragImageSize.width / 2,
            y: mouseLoc.y - dragImageSize.height / 2,
            width: dragImageSize.width,
            height: dragImageSize.height
        )
        draggingItem.setDraggingFrame(dragFrame, contents: dragImage)

        self.beginDraggingSession(items: [draggingItem], event: event, source: self)
    }

    private func writeImageToTemporaryFile(_ image: NSImage, fileName: String? = nil) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-shoot-drag", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let filename: String
        if let fileName = fileName {
            filename = fileName
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
            filename = "ScreenShoot-\(formatter.string(from: Date())).png"
        }

        let fileURL = tempDir.appendingPathComponent(filename)

        guard let pngData = image.pngData() else {
            NSLog("[ThumbnailPanel] Failed to generate PNG data for drag temp file")
            return nil
        }

        do {
            try pngData.write(to: fileURL)
            return fileURL
        } catch {
            NSLog("[ThumbnailPanel] Failed to write drag temp file: \(error)")
            return nil
        }
    }

    private func cleanStaleDragTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-shoot-drag", isDirectory: true)
        guard FileManager.default.fileExists(atPath: tempDir.path) else { return }

        if let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Actions

    private func openInFinder() {
        guard let url = screenshotURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Right-Click Menu

    override func rightMouseDown(with event: NSEvent) {
        NSLog("[ThumbnailPanel] rightMouseDown – hasFileOnDisk=\(hasFileOnDisk), screenshotURL=\(screenshotURL?.path ?? "nil"), image=\(screenshotImage != nil)")

        let menu = NSMenu()

        let finderItem = NSMenuItem(title: "Open in Finder", action: #selector(openInFinderAction), keyEquivalent: "")
        finderItem.target = self

        let copyItem = NSMenuItem(title: "Copy to Clipboard", action: #selector(copyToClipboard), keyEquivalent: "")
        copyItem.target = self

        let editItem = NSMenuItem(title: "Edit", action: #selector(editScreenshot), keyEquivalent: "")
        editItem.target = self

        let deleteItem = NSMenuItem(title: "Delete Screenshot", action: #selector(deleteScreenshot), keyEquivalent: "")
        deleteItem.target = self

        let dismissItem = NSMenuItem(title: "Dismiss", action: #selector(dismissPanel), keyEquivalent: "")
        dismissItem.target = self

        if hasFileOnDisk {
            menu.addItem(finderItem)
            menu.addItem(copyItem)
            menu.addItem(editItem)
            menu.addItem(deleteItem)
        } else {
            menu.addItem(copyItem)
            menu.addItem(editItem)
        }

        menu.addItem(.separator())
        menu.addItem(dismissItem)

        if let contentView = contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
        }
    }

    @objc private func openInFinderAction() {
        openInFinder()
    }

    @objc private func editScreenshot() {
        NSLog("[ThumbnailPanel] editScreenshot called – image=\(screenshotImage != nil), onEdit=\(onEdit != nil)")
        guard let image = screenshotImage else { return }
        onEdit?(image, screenshotURL)
    }

    @objc private func copyToClipboard() {
        guard let image = screenshotImage else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        let fileName = "ScreenShoot-\(formatter.string(from: Date())).png"

        if let url = screenshotURL {
            // Use the existing file on disk
            pasteboard.writeObjects([image, url as NSURL])
        } else {
            // Create a named temp file so paste-as-file works everywhere
            guard let tempURL = writeImageToTemporaryFile(image, fileName: fileName) else {
                // Fallback: paste image only
                pasteboard.writeObjects([image])
                showCopyFeedback()
                return
            }
            clipboardTempURL = tempURL
            pasteboard.writeObjects([image, tempURL as NSURL])
        }

        showCopyFeedback()
    }

    @objc private func deleteScreenshot() {
        guard let url = screenshotURL else { return }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            NSLog("[ThumbnailPanel] Failed to delete screenshot: \(error)")
        }

        dismissPanel()
    }

    private func showCopyFeedback() {
        guard let contentView = contentView else { return }

        let label = NSTextField(labelWithString: "Copied!")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        label.layer?.cornerRadius = 6

        let labelSize = label.intrinsicContentSize
        label.frame = NSRect(
            x: (contentView.frame.width - labelSize.width - 16) / 2,
            y: (contentView.frame.height - labelSize.height) / 2,
            width: labelSize.width + 16,
            height: labelSize.height + 8
        )

        contentView.addSubview(label)
        label.alphaValue = 0

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            label.animator().alphaValue = 1.0
        }, completionHandler: { [weak label] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak label] in
                guard let label = label else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    label.animator().alphaValue = 0
                }, completionHandler: { [weak label] in
                    label?.removeFromSuperview()
                })
            }
        })
    }
}

// MARK: - NSDraggingSource

extension ThumbnailPanel: NSDraggingSource {

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        ignoresMouseEvents = true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        ignoresMouseEvents = false

        // Delay temp cleanup so the receiving app has time to read the file
        if let tempURL = lastDragTempURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            lastDragTempURL = nil
        }

        if operation.contains(.copy) {
            dismissPanel()
        }
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        return true
    }
}

// MARK: - NSImage Extension

extension NSImage {
    func resized(to size: NSSize) -> NSImage {
        let resized = NSImage(size: size)
        resized.lockFocus()
        draw(in: NSRect(origin: .zero, size: size),
             from: NSRect(origin: .zero, size: self.size),
             operation: .copy,
             fraction: 1.0)
        resized.unlockFocus()
        return resized
    }

    func pngData() -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
