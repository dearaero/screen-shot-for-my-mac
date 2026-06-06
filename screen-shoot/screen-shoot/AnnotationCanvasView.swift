import AppKit

// MARK: - Annotation Canvas

final class AnnotationCanvasView: NSView {

    // MARK: - Properties

    private var backgroundImage: NSImage?
    private var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?
    private var isDrawing = false
    private var nextNumber = 1

    var selectedTool: AnnotationTool = .pen
    var selectedColor: NSColor = .systemRed
    var selectedLineWidth: CGFloat = 3.0

    var onAnnotationsChanged: (() -> Void)?

    private var textField: NSTextField?
    private var textAnnotation: Annotation?

    // MARK: - Init

    init(image: NSImage) {
        self.backgroundImage = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 4
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Aspect-Fit Helpers

    private var displayRect: NSRect {
        guard let image = backgroundImage, image.size.width > 0, image.size.height > 0 else {
            return bounds
        }
        return aspectFitRect(for: image.size, in: bounds)
    }

    private func aspectFitRect(for imageSize: NSSize, in rect: NSRect) -> NSRect {
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let newWidth = imageSize.width * scale
        let newHeight = imageSize.height * scale
        let x = rect.minX + (rect.width - newWidth) / 2
        let y = rect.minY + (rect.height - newHeight) / 2
        return NSRect(x: x, y: y, width: newWidth, height: newHeight)
    }

    /// Converts a point from view coordinates to image coordinates
    private func imagePoint(from viewPoint: NSPoint) -> NSPoint? {
        guard let image = backgroundImage else { return nil }
        let rect = displayRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        let scaleX = image.size.width / rect.width
        let scaleY = image.size.height / rect.height
        return NSPoint(
            x: (viewPoint.x - rect.minX) * scaleX,
            y: (viewPoint.y - rect.minY) * scaleY
        )
    }

    /// Converts a point from image coordinates to view coordinates
    private func viewPoint(from imagePoint: NSPoint) -> NSPoint? {
        guard let image = backgroundImage else { return nil }
        let rect = displayRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        let scaleX = rect.width / image.size.width
        let scaleY = rect.height / image.size.height
        return NSPoint(
            x: rect.minX + imagePoint.x * scaleX,
            y: rect.minY + imagePoint.y * scaleY
        )
    }

    /// Converts an image rect to view rect
    private func viewRect(from imageRect: NSRect) -> NSRect? {
        guard let topLeft = viewPoint(from: NSPoint(x: imageRect.minX, y: imageRect.maxY)),
              let bottomRight = viewPoint(from: NSPoint(x: imageRect.maxX, y: imageRect.minY)) else {
            return nil
        }
        return NSRect(
            x: topLeft.x,
            y: bottomRight.y,
            width: bottomRight.x - topLeft.x,
            height: topLeft.y - bottomRight.y
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Fill background
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        guard let image = backgroundImage else { return }

        let rect = displayRect
        image.draw(in: rect)

        // Apply blur annotations before drawing overlays
        for annotation in annotations where annotation.tool == .blur {
            drawBlurAnnotation(annotation, in: rect, imageSize: image.size)
        }
        if let current = currentAnnotation, current.tool == .blur {
            drawBlurAnnotation(current, in: rect, imageSize: image.size)
        }

        // Draw all non-blur annotations scaled to display rect
        context.saveGState()
        let scaleX = rect.width / image.size.width
        let scaleY = rect.height / image.size.height
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: scaleX, y: scaleY)

        for annotation in annotations where annotation.tool != .blur {
            annotation.draw(in: context)
        }

        if let current = currentAnnotation, current.tool != .blur {
            current.draw(in: context)
        }

        context.restoreGState()
    }

    private func drawBlurAnnotation(_ annotation: Annotation, in displayRect: NSRect, imageSize: NSSize) {
        guard annotation.points.count >= 2,
              let blurred = applyPixelation(for: annotation, imageSize: imageSize) else { return }

        let start = annotation.points[0]
        let end = annotation.points[annotation.points.count - 1]
        let imageRect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        guard let viewR = viewRect(from: imageRect), viewR.width > 0, viewR.height > 0 else { return }
        blurred.draw(in: viewR)
    }

    private func applyPixelation(for annotation: Annotation, imageSize: NSSize) -> NSImage? {
        guard let source = backgroundImage else { return nil }
        guard annotation.points.count >= 2 else { return nil }

        let start = annotation.points[0]
        let end = annotation.points[annotation.points.count - 1]
        let cropRect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }

        // Crop from original image
        guard let tiff = source.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage,
              let croppedCG = cgImage.cropping(to: cropRect) else { return nil }

        // Enterprise pixelation: fixed visible pixel count for strong effect
        let targetPixelCount: CGFloat = 10
        let scaleX = max(1.0, cropRect.width / targetPixelCount)
        let scaleY = max(1.0, cropRect.height / targetPixelCount)
        let pixelScale = max(scaleX, scaleY)

        let smallSize = NSSize(
            width: max(1, floor(cropRect.width / pixelScale)),
            height: max(1, floor(cropRect.height / pixelScale))
        )

        // Downscale with nearest-neighbor
        let smallImage = NSImage(size: smallSize)
        smallImage.lockFocus()
        if let ctx = NSGraphicsContext.current {
            ctx.imageInterpolation = .none
        }
        NSImage(cgImage: croppedCG, size: cropRect.size).draw(
            in: NSRect(origin: .zero, size: smallSize),
            from: NSRect(origin: .zero, size: cropRect.size),
            operation: .copy, fraction: 1.0
        )
        smallImage.unlockFocus()

        // Upscale with nearest-neighbor (preserves pixelated look)
        let pixelated = NSImage(size: cropRect.size)
        pixelated.lockFocus()
        if let ctx = NSGraphicsContext.current {
            ctx.imageInterpolation = .none
        }
        smallImage.draw(
            in: NSRect(origin: .zero, size: cropRect.size),
            from: NSRect(origin: .zero, size: smallSize),
            operation: .copy, fraction: 1.0
        )

        // Extra enterprise obfuscation: subtle noise overlay
        let noiseAlpha: CGFloat = 0.12
        let noiseStep: CGFloat = 8
        for x in stride(from: 0, to: cropRect.width, by: noiseStep) {
            for y in stride(from: 0, to: cropRect.height, by: noiseStep) {
                let gray = CGFloat.random(in: 0...1)
                NSColor(white: gray, alpha: noiseAlpha).setFill()
                NSRect(x: x, y: y, width: noiseStep, height: noiseStep).fill()
            }
        }

        pixelated.unlockFocus()
        return pixelated
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        guard backgroundImage != nil else { return }

        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let imgPoint = imagePoint(from: viewPoint) else { return }

        if selectedTool == .text {
            showTextInput(at: viewPoint, imagePoint: imgPoint)
            return
        }

        if selectedTool == .number {
            var annotation = Annotation(tool: .number, color: selectedColor, lineWidth: selectedLineWidth)
            annotation.points = [imgPoint]
            annotation.text = "\(nextNumber)"
            nextNumber += 1
            addAnnotation(annotation)
            needsDisplay = true
            return
        }

        isDrawing = true
        var annotation = Annotation(tool: selectedTool, color: selectedColor, lineWidth: selectedLineWidth)
        annotation.points = [imgPoint]
        currentAnnotation = annotation

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDrawing, var annotation = currentAnnotation else { return }

        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let imgPoint = imagePoint(from: viewPoint) else { return }

        annotation.points.append(imgPoint)
        currentAnnotation = annotation

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDrawing, let annotation = currentAnnotation else { return }

        isDrawing = false
        currentAnnotation = nil

        if annotation.points.count >= 2 || annotation.tool == .text {
            addAnnotation(annotation)
        }

        needsDisplay = true
    }

    // MARK: - Annotation Management

    func addAnnotation(_ annotation: Annotation) {
        annotations.append(annotation)
        onAnnotationsChanged?()
    }

    func removeLastAnnotation() {
        guard !annotations.isEmpty else { return }
        let removed = annotations.removeLast()
        if removed.tool == .number {
            nextNumber = max(1, nextNumber - 1)
        }
        needsDisplay = true
        onAnnotationsChanged?()
    }

    func addAnnotationBack(_ annotation: Annotation) {
        annotations.append(annotation)
        if annotation.tool == .number, let numStr = annotation.text, let num = Int(numStr) {
            nextNumber = max(nextNumber, num + 1)
        }
        needsDisplay = true
        onAnnotationsChanged?()
    }

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { false }

    var allAnnotations: [Annotation] { annotations }

    // MARK: - Text Input

    private func showTextInput(at viewPoint: NSPoint, imagePoint: NSPoint) {
        guard textField == nil else { return }

        let field = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y - 20, width: 200, height: 24))
        field.font = NSFont.systemFont(ofSize: max(14, selectedLineWidth * 2))
        field.textColor = selectedColor
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBezeled = false
        field.focusRingType = .none
        field.placeholderString = "Type here..."
        field.target = self
        field.action = #selector(commitText)
        field.delegate = self

        addSubview(field)
        window?.makeFirstResponder(field)

        textField = field

        var annotation = Annotation(tool: .text, color: selectedColor, lineWidth: selectedLineWidth)
        annotation.points = [imagePoint]
        textAnnotation = annotation
    }

    @objc private func commitText() {
        guard let field = textField, var annotation = textAnnotation else { return }
        let text = field.stringValue
        field.removeFromSuperview()
        textField = nil
        textAnnotation = nil

        guard !text.isEmpty else {
            needsDisplay = true
            return
        }

        annotation.text = text
        addAnnotation(annotation)
        needsDisplay = true
    }

    // MARK: - Export

    func renderedImage() -> NSImage? {
        guard let image = backgroundImage else { return nil }

        let size = image.size
        let newImage = NSImage(size: size)
        newImage.lockFocus()

        // Draw background at original size
        image.draw(in: NSRect(origin: .zero, size: size))

        guard let context = NSGraphicsContext.current?.cgContext else {
            newImage.unlockFocus()
            return newImage
        }

        // Apply blur annotations at original size
        for annotation in annotations where annotation.tool == .blur {
            guard let blurred = applyPixelation(for: annotation, imageSize: size) else { continue }
            let start = annotation.points[0]
            let end = annotation.points[annotation.points.count - 1]
            let blurRect = NSRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            blurred.draw(in: blurRect)
        }

        // Draw non-blur annotations at original size
        for annotation in annotations where annotation.tool != .blur {
            annotation.draw(in: context)
        }

        newImage.unlockFocus()
        return newImage
    }
}

// MARK: - NSTextFieldDelegate

extension AnnotationCanvasView: NSTextFieldDelegate {

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitText()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.removeFromSuperview()
            textField = nil
            textAnnotation = nil
            return true
        }
        return false
    }
}
