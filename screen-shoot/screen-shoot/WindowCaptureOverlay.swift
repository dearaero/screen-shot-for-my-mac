import AppKit
import CoreGraphics

// MARK: - Overlay Window

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Window Capture Overlay

final class WindowCaptureOverlay {

    private var overlayWindow: OverlayWindow?
    private var overlayView: WindowOverlayView?
    private var onComplete: ((Int32) -> Void)?
    private var onCancel: (() -> Void)?
    private var monitorHandlers: [Any] = []

    deinit {
        dismiss()
    }

    func show(onCapture: @escaping (Int32) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onCapture
        self.onCancel = onCancel

        // Find the screen containing the mouse cursor for multi-monitor support
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            NSLog("[WindowCaptureOverlay] No screen found, cancelling")
            onCancel()
            return
        }

        let screenFrame = screen.frame
        NSLog("[WindowCaptureOverlay] Showing overlay on screen: \(screenFrame)")

        let window = OverlayWindow(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.acceptsMouseMovedEvents = true

        let view = WindowOverlayView(frame: screenFrame)
        view.onWindowSelected = { [weak self] windowID in
            NSLog("[WindowCaptureOverlay] Window selected: \(windowID)")
            self?.dismiss()
            self?.onComplete?(windowID)
        }
        view.onCancel = { [weak self] in
            NSLog("[WindowCaptureOverlay] Cancelled from view")
            self?.dismiss()
            self?.onCancel?()
        }

        window.contentView = view
        self.overlayView = view
        self.overlayWindow = window

        setupEventMonitors()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSLog("[WindowCaptureOverlay] Overlay is key and front")
    }

    // MARK: - Event Monitors

    private func setupEventMonitors() {
        if let keyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 {
                NSLog("[WindowCaptureOverlay] Escape pressed")
                self?.dismiss()
                self?.onCancel?()
                return nil
            }
            return event
        }) {
            monitorHandlers.append(keyDown)
        }
    }

    private func dismiss() {
        guard !monitorHandlers.isEmpty || overlayWindow != nil else { return }
        NSLog("[WindowCaptureOverlay] Dismissing")
        for handler in monitorHandlers {
            NSEvent.removeMonitor(handler)
        }
        monitorHandlers.removeAll()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayView = nil
    }
}

// MARK: - Overlay View

final class WindowOverlayView: NSView {

    private var windowList: [(id: Int32, screenBounds: CGRect, name: String)] = []
    private(set) var hoveredWindowID: Int32?
    private let viewHeight: CGFloat

    var onWindowSelected: ((Int32) -> Void)?
    var onCancel: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        self.viewHeight = frame.height
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        refreshWindowList()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        self.trackingArea = newTrackingArea
    }

    // MARK: - Window Detection

    private func refreshWindowList() {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            NSLog("[WindowOverlayView] Failed to get window list")
            return
        }

        var windows: [(id: Int32, screenBounds: CGRect, name: String)] = []

        for info in windowInfo {
            guard let windowID = info[kCGWindowNumber as String] as? Int32,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = info[kCGWindowLayer as String] as? Int32,
                  layer == 0 else {
                continue
            }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? "Unknown"

            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            let w = boundsDict["Width"] ?? 0
            let h = boundsDict["Height"] ?? 0

            guard w > 80, h > 40 else { continue }

            let screenRect = CGRect(x: x, y: y, width: w, height: h)
            windows.append((id: windowID, screenBounds: screenRect, name: ownerName))
        }

        // Preserve front-to-back z-order
        windowList = windows
        NSLog("[WindowOverlayView] Found \(windowList.count) windows")
    }

    // MARK: - Mouse Handling

    override func mouseMoved(with event: NSEvent) {
        updateHoveredWindow(at: event.locationInWindow)
    }

    override func mouseDown(with event: NSEvent) {
        updateHoveredWindow(at: event.locationInWindow)

        guard let windowID = hoveredWindowID else {
            NSLog("[WindowOverlayView] Clicked outside any window, cancelling")
            onCancel?()
            return
        }
        NSLog("[WindowOverlayView] Clicked window: \(windowID)")
        onWindowSelected?(windowID)
    }

    private func updateHoveredWindow(at pointInWindow: NSPoint) {
        var foundID: Int32?
        for window in windowList {
            if window.screenBounds.contains(pointInWindow) {
                foundID = window.id
                break
            }
        }

        if hoveredWindowID != foundID {
            hoveredWindowID = foundID
            if let foundID = foundID {
                NSLog("[WindowOverlayView] Hovered window: \(foundID)")
            }
            needsDisplay = true
        }
    }

    // MARK: - Drawing

    private func viewRect(from screenRect: CGRect) -> CGRect {
        return CGRect(
            x: screenRect.minX,
            y: viewHeight - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.5).setFill()
        bounds.fill()

        guard let windowID = hoveredWindowID,
              let window = windowList.first(where: { $0.id == windowID }) else {
            return
        }

        let rect = viewRect(from: window.screenBounds).insetBy(dx: -2, dy: -2)
        let cornerRadius: CGFloat = 16

        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.2).setFill()
        path.fill()

        let border = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        border.lineWidth = 3
        NSColor.white.setStroke()
        border.stroke()

        let labelText = window.name as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = labelText.size(withAttributes: attrs)
        let labelRect = NSRect(
            x: rect.midX - (size.width + 16) / 2,
            y: rect.maxY + 10,
            width: size.width + 16,
            height: size.height + 8
        )

        let labelBg = NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.8).setFill()
        labelBg.fill()
        labelText.draw(in: NSRect(x: labelRect.minX + 8, y: labelRect.minY + 4, width: size.width, height: size.height), withAttributes: attrs)
    }
}
