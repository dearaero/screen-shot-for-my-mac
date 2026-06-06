import AppKit

// MARK: - Annotation Type

enum AnnotationTool: CaseIterable {
    case pen
    case arrow
    case rectangle
    case ellipse
    case text
    case blur
    case number

    var iconName: String {
        switch self {
        case .pen: return "pencil"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "square"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .blur: return "eye.slash"
        case .number: return "number"
        }
    }

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .blur: return "Blur"
        case .number: return "Number"
        }
    }
}

// MARK: - Annotation Model

struct Annotation: Identifiable {
    let id: UUID
    var tool: AnnotationTool
    var points: [NSPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text: String?

    init(tool: AnnotationTool, color: NSColor, lineWidth: CGFloat) {
        self.id = UUID()
        self.tool = tool
        self.points = []
        self.color = color
        self.lineWidth = lineWidth
        self.text = nil
    }
}

// MARK: - Drawing Helpers

extension Annotation {

    func draw(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch tool {
        case .pen:
            drawPen(in: context)
        case .arrow:
            drawArrow(in: context)
        case .rectangle:
            drawRectangle(in: context)
        case .ellipse:
            drawEllipse(in: context)
        case .text:
            drawText()
        case .blur:
            drawBlurFrame(in: context)
        case .number:
            drawNumber()
        }
    }

    private func drawPen(in context: CGContext) {
        guard points.count > 1 else { return }
        context.beginPath()
        context.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for i in 1..<points.count {
            context.addLine(to: CGPoint(x: points[i].x, y: points[i].y))
        }
        context.strokePath()
    }

    private func drawArrow(in context: CGContext) {
        guard points.count >= 2 else { return }
        let start = points[0]
        let end = points[points.count - 1]

        context.beginPath()
        context.move(to: CGPoint(x: start.x, y: start.y))
        context.addLine(to: CGPoint(x: end.x, y: end.y))
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = max(12, lineWidth * 3)
        let arrowAngle: CGFloat = .pi / 6

        let x1 = end.x - arrowLength * cos(angle - arrowAngle)
        let y1 = end.y - arrowLength * sin(angle - arrowAngle)
        let x2 = end.x - arrowLength * cos(angle + arrowAngle)
        let y2 = end.y - arrowLength * sin(angle + arrowAngle)

        context.beginPath()
        context.move(to: CGPoint(x: end.x, y: end.y))
        context.addLine(to: CGPoint(x: x1, y: y1))
        context.move(to: CGPoint(x: end.x, y: end.y))
        context.addLine(to: CGPoint(x: x2, y: y2))
        context.strokePath()
    }

    private func drawRectangle(in context: CGContext) {
        guard points.count >= 2 else { return }
        let start = points[0]
        let end = points[points.count - 1]
        let rect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        context.setFillColor(color.withAlphaComponent(0.15).cgColor)
        context.fill(rect)
        context.stroke(rect)
    }

    private func drawEllipse(in context: CGContext) {
        guard points.count >= 2 else { return }
        let start = points[0]
        let end = points[points.count - 1]
        let rect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        let path = CGPath(ellipseIn: rect, transform: nil)
        context.setFillColor(color.withAlphaComponent(0.15).cgColor)
        context.addPath(path)
        context.fillPath()
        context.addPath(path)
        context.strokePath()
    }

    private func drawText() {
        guard let text = text, let point = points.first else { return }
        let font = NSFont.systemFont(ofSize: max(14, lineWidth * 2))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let size = attributedString.size()
        let rect = NSRect(x: point.x, y: point.y - size.height, width: size.width + 4, height: size.height)
        attributedString.draw(in: rect)
    }

    private func drawBlurFrame(in context: CGContext) {
        guard points.count >= 2 else { return }
        let start = points[0]
        let end = points[points.count - 1]
        let rect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        // Dashed border to indicate blur region
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.5)
        context.stroke(rect)
        // Diagonal cross-hatch pattern
        context.beginPath()
        context.move(to: CGPoint(x: rect.minX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        context.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        context.strokePath()
    }

    private func drawNumber() {
        guard let text = text, let point = points.first else { return }
        let diameter: CGFloat = max(28, lineWidth * 6)
        let circleRect = NSRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )

        // Circle background
        let circlePath = NSBezierPath(ovalIn: circleRect)
        color.setFill()
        circlePath.fill()

        // Circle border
        NSColor.white.setStroke()
        circlePath.lineWidth = 2
        circlePath.stroke()

        // Number text centered
        let font = NSFont.systemFont(ofSize: diameter * 0.5, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = NSRect(
            x: circleRect.midX - textSize.width / 2,
            y: circleRect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedString.draw(in: textRect)
    }
}
