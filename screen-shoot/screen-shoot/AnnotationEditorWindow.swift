import AppKit

// MARK: - Annotation Editor Window

final class AnnotationEditorWindow: NSWindow {

    // MARK: - Properties

    private var canvasView: AnnotationCanvasView!
    private let annotationUndoManager = UndoManager()
    private var originalURL: URL?
    private var onSave: ((NSImage, URL?) -> Void)?

    private var colorWellRef: NSColorWell?
    private var sliderRef: NSSlider?

    // MARK: - Init

    init(image: NSImage, originalURL: URL?, onSave: @escaping (NSImage, URL?) -> Void) {
        self.originalURL = originalURL
        self.onSave = onSave

        let canvasSize = image.size
        let toolbarHeight: CGFloat = 52
        let padding: CGFloat = 20
        let minWindowWidth: CGFloat = 720
        let windowWidth = max(canvasSize.width + padding * 2, minWindowWidth)
        let windowHeight = canvasSize.height + toolbarHeight + padding * 2

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let windowX = screenFrame.midX - windowWidth / 2
        let windowY = screenFrame.midY - windowHeight / 2

        super.init(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "Edit Screenshot"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 600, height: 350)
        level = .floating

        setupUI(image: image, canvasSize: canvasSize, toolbarHeight: toolbarHeight)
        setupUndoRedo()
    }

    // MARK: - UI Setup

    private func setupUI(image: NSImage, canvasSize: NSSize, toolbarHeight: CGFloat) {
        // Use the actual contentView frame (excludes title bar)
        let contentSize = contentView?.frame.size ?? frame.size
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]

        // Toolbar — pinned to top of content area
        let toolbar = NSView(frame: NSRect(x: 0, y: contentSize.height - toolbarHeight, width: contentSize.width, height: toolbarHeight))
        toolbar.autoresizingMask = [.width, .minYMargin]
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        // Left group wrapper
        let leftGroup = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: toolbarHeight))
        leftGroup.autoresizingMask = [.maxXMargin]
        var leftX: CGFloat = 12

        // Tool segmented control (icon-only to save space)
        let toolControl = NSSegmentedControl(
            images: AnnotationTool.allCases.map { NSImage(systemSymbolName: $0.iconName, accessibilityDescription: $0.label)! },
            trackingMode: .selectOne,
            target: self,
            action: #selector(toolChanged(_:))
        )
        toolControl.selectedSegment = 0
        toolControl.sizeToFit()
        toolControl.frame.origin = NSPoint(x: leftX, y: (toolbarHeight - toolControl.frame.height) / 2)
        leftGroup.addSubview(toolControl)
        leftX += toolControl.frame.width + 12

        // Separator
        let sep1 = NSView(frame: NSRect(x: leftX, y: 10, width: 1, height: toolbarHeight - 20))
        sep1.wantsLayer = true
        sep1.layer?.backgroundColor = NSColor.separatorColor.cgColor
        leftGroup.addSubview(sep1)
        leftX += 10

        // Color well
        let colorWell = NSColorWell(frame: NSRect(x: leftX, y: (toolbarHeight - 28) / 2, width: 28, height: 28))
        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        leftGroup.addSubview(colorWell)
        self.colorWellRef = colorWell
        leftX += 36

        let colorLabel = NSTextField(labelWithString: "Color")
        colorLabel.font = .systemFont(ofSize: 11)
        colorLabel.textColor = .secondaryLabelColor
        colorLabel.sizeToFit()
        colorLabel.frame.origin = NSPoint(x: leftX, y: (toolbarHeight - colorLabel.frame.height) / 2)
        leftGroup.addSubview(colorLabel)
        leftX += colorLabel.frame.width + 14

        // Separator
        let sep2 = NSView(frame: NSRect(x: leftX, y: 10, width: 1, height: toolbarHeight - 20))
        sep2.wantsLayer = true
        sep2.layer?.backgroundColor = NSColor.separatorColor.cgColor
        leftGroup.addSubview(sep2)
        leftX += 10

        // Line width slider
        let widthLabel = NSTextField(labelWithString: "Width:")
        widthLabel.font = .systemFont(ofSize: 11)
        widthLabel.textColor = .secondaryLabelColor
        widthLabel.sizeToFit()
        widthLabel.frame.origin = NSPoint(x: leftX, y: (toolbarHeight - widthLabel.frame.height) / 2)
        leftGroup.addSubview(widthLabel)
        leftX += widthLabel.frame.width + 6

        let slider = NSSlider(value: 3.0, minValue: 1.0, maxValue: 12.0, target: self, action: #selector(widthChanged(_:)))
        slider.frame = NSRect(x: leftX, y: (toolbarHeight - 20) / 2, width: 80, height: 20)
        leftGroup.addSubview(slider)
        self.sliderRef = slider
        leftX += 90

        // Separator
        let sep3 = NSView(frame: NSRect(x: leftX, y: 10, width: 1, height: toolbarHeight - 20))
        sep3.wantsLayer = true
        sep3.layer?.backgroundColor = NSColor.separatorColor.cgColor
        leftGroup.addSubview(sep3)
        leftX += 10

        // Undo/Redo buttons
        let undoButton = NSButton(frame: NSRect(x: leftX, y: (toolbarHeight - 28) / 2, width: 28, height: 28))
        undoButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
        undoButton.bezelStyle = .smallSquare
        undoButton.isBordered = false
        undoButton.target = self
        undoButton.action = #selector(undoAction)
        leftGroup.addSubview(undoButton)
        leftX += 30

        let redoButton = NSButton(frame: NSRect(x: leftX, y: (toolbarHeight - 28) / 2, width: 28, height: 28))
        redoButton.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")
        redoButton.bezelStyle = .smallSquare
        redoButton.isBordered = false
        redoButton.target = self
        redoButton.action = #selector(redoAction)
        leftGroup.addSubview(redoButton)
        leftX += 28

        leftGroup.frame.size.width = leftX + 4
        toolbar.addSubview(leftGroup)

        // Save/Cancel buttons — pinned to right edge
        let cancelButton = NSButton(frame: NSRect(x: toolbar.frame.width - 176, y: (toolbarHeight - 28) / 2, width: 78, height: 28))
        cancelButton.autoresizingMask = [.minXMargin]
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction)
        toolbar.addSubview(cancelButton)

        let saveButton = NSButton(frame: NSRect(x: toolbar.frame.width - 94, y: (toolbarHeight - 28) / 2, width: 78, height: 28))
        saveButton.autoresizingMask = [.minXMargin]
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveAction)
        toolbar.addSubview(saveButton)

        container.addSubview(toolbar)

        // Canvas fills remaining content area below toolbar with padding
        let canvasPadding: CGFloat = 24
        let canvasFrame = NSRect(
            x: canvasPadding,
            y: canvasPadding,
            width: contentSize.width - canvasPadding * 2,
            height: contentSize.height - toolbarHeight - canvasPadding * 2
        )
        canvasView = AnnotationCanvasView(image: image)
        canvasView.frame = canvasFrame
        canvasView.autoresizingMask = [.width, .height]
        canvasView.selectedTool = .pen
        canvasView.selectedColor = colorWell.color
        canvasView.selectedLineWidth = CGFloat(slider.doubleValue)

        canvasView.onAnnotationsChanged = { [weak self] in
            self?.updateUndoRedoButtons()
        }

        container.addSubview(canvasView)
        contentView = container
    }

    // MARK: - Toolbar Actions

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        let tool = AnnotationTool.allCases[sender.selectedSegment]
        canvasView.selectedTool = tool
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        canvasView.selectedColor = sender.color
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        canvasView.selectedLineWidth = CGFloat(sender.doubleValue)
    }

    // MARK: - Undo / Redo

    private func setupUndoRedo() {
        canvasView.onAnnotationsChanged = { [weak self] in
            guard let self = self else { return }
            self.updateUndoRedoButtons()
        }
    }

    @objc private func undoAction() {
        guard canvasView.canUndo else { return }

        let annotation = canvasView.allAnnotations.last
        canvasView.removeLastAnnotation()

        if let annotation = annotation {
            annotationUndoManager.registerUndo(withTarget: self) { [weak self] _ in
                self?.canvasView.addAnnotationBack(annotation)
            }
        }

        updateUndoRedoButtons()
    }

    @objc private func redoAction() {
        annotationUndoManager.redo()
        updateUndoRedoButtons()
    }

    private func updateUndoRedoButtons() {
        // Buttons are updated via canUndo state
    }

    // MARK: - Save / Cancel

    @objc private func saveAction() {
        guard let renderedImage = canvasView.renderedImage() else {
            close()
            return
        }
        onSave?(renderedImage, originalURL)
        close()
    }

    @objc private func cancelAction() {
        close()
    }

    override func cancelOperation(_ sender: Any?) {
        cancelAction()
    }
}
