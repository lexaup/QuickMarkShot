import AppKit
import Carbon
import UniformTypeIdentifiers

enum MarkTool: Int, CaseIterable {
    case rectangle
    case ellipse
    case arrow
    case pen

    var title: String {
        switch self {
        case .rectangle: return "矩形"
        case .ellipse: return "圆形"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        }
    }
}

struct Mark {
    let tool: MarkTool
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint]
    let color: NSColor
    let lineWidth: CGFloat
}

final class AnnotationCanvas: NSView {
    let sourceImage: NSImage
    var selectedTool: MarkTool = .arrow
    var selectedColor: NSColor = .systemRed
    var selectedLineWidth: CGFloat = 4
    var onHistoryChange: (() -> Void)?

    private(set) var marks: [Mark] = []
    private(set) var redoMarks: [Mark] = []
    private var activeMark: Mark?

    init(image: NSImage) {
        self.sourceImage = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private var imageRect: CGRect {
        let padding: CGFloat = 28
        let available = bounds.insetBy(dx: padding, dy: padding)
        guard sourceImage.size.width > 0, sourceImage.size.height > 0,
              available.width > 0, available.height > 0 else { return .zero }

        let scale = min(available.width / sourceImage.size.width,
                        available.height / sourceImage.size.height)
        let size = CGSize(width: sourceImage.size.width * scale,
                          height: sourceImage.size.height * scale)
        return CGRect(x: available.midX - size.width / 2,
                      y: available.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    private var displayScale: CGFloat {
        guard sourceImage.size.width > 0 else { return 1 }
        return imageRect.width / sourceImage.size.width
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = imageRect
        guard !rect.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = CGSize(width: 0, height: -5)
        shadow.set()
        NSColor.black.withAlphaComponent(0.06).setFill()
        NSBezierPath(rect: rect).fill()
        NSGraphicsContext.restoreGraphicsState()

        sourceImage.draw(in: rect,
                         from: .zero,
                         operation: .copy,
                         fraction: 1,
                         respectFlipped: false,
                         hints: [.interpolation: NSImageInterpolation.high])

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        for mark in marks {
            draw(mark, in: rect, scale: displayScale)
        }
        if let activeMark {
            draw(activeMark, in: rect, scale: displayScale)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(viewPoint) else { return }

        let point = imagePoint(from: viewPoint)
        activeMark = Mark(tool: selectedTool,
                          start: point,
                          end: point,
                          points: [point],
                          color: selectedColor.usingColorSpace(.deviceRGB) ?? selectedColor,
                          lineWidth: selectedLineWidth / max(displayScale, 0.01))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var mark = activeMark else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = constrainedPoint(from: viewPoint, for: mark, event: event)

        mark.end = point
        if mark.tool == .pen {
            if let last = mark.points.last,
               hypot(point.x - last.x, point.y - last.y) > 0.8 / max(displayScale, 0.01) {
                mark.points.append(point)
            }
        }
        activeMark = mark
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var mark = activeMark else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        mark.end = constrainedPoint(from: viewPoint, for: mark, event: event)
        if mark.tool == .pen, mark.points.count == 1 {
            mark.points.append(mark.end)
        }

        activeMark = nil
        let distance = hypot(mark.end.x - mark.start.x, mark.end.y - mark.start.y)
        if distance > 1 / max(displayScale, 0.01) || mark.points.count > 2 {
            marks.append(mark)
            redoMarks.removeAll()
            onHistoryChange?()
        }
        needsDisplay = true
    }

    func undo() {
        guard let mark = marks.popLast() else { return }
        redoMarks.append(mark)
        onHistoryChange?()
        needsDisplay = true
    }

    func redo() {
        guard let mark = redoMarks.popLast() else { return }
        marks.append(mark)
        onHistoryChange?()
        needsDisplay = true
    }

    func removeAllMarks() {
        guard !marks.isEmpty else { return }
        redoMarks.append(contentsOf: marks.reversed())
        marks.removeAll()
        onHistoryChange?()
        needsDisplay = true
    }

    func flattenedPNG() -> Data? {
        guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: pixelWidth,
                                            pixelsHigh: pixelHeight,
                                            bitsPerSample: 8,
                                            samplesPerPixel: 4,
                                            hasAlpha: true,
                                            isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0,
                                            bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixelWidth) / sourceImage.size.width,
                                  y: CGFloat(pixelHeight) / sourceImage.size.height)
        sourceImage.draw(in: CGRect(origin: .zero, size: sourceImage.size),
                         from: .zero,
                         operation: .copy,
                         fraction: 1,
                         respectFlipped: false,
                         hints: [.interpolation: NSImageInterpolation.high])
        for mark in marks {
            draw(mark,
                 in: CGRect(origin: .zero, size: sourceImage.size),
                 scale: 1)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        let rect = imageRect
        let scale = displayScale
        return CGPoint(x: (viewPoint.x - rect.minX) / scale,
                       y: (viewPoint.y - rect.minY) / scale)
    }

    private func clampedImagePoint(from viewPoint: CGPoint) -> CGPoint {
        let point = imagePoint(from: viewPoint)
        return CGPoint(x: min(max(point.x, 0), sourceImage.size.width),
                       y: min(max(point.y, 0), sourceImage.size.height))
    }

    private func constrainedPoint(from viewPoint: CGPoint, for mark: Mark, event: NSEvent) -> CGPoint {
        let point = clampedImagePoint(from: viewPoint)
        guard event.modifierFlags.contains(.shift),
              mark.tool == .rectangle || mark.tool == .ellipse else { return point }

        let dx = point.x - mark.start.x
        let dy = point.y - mark.start.y
        let side = min(max(abs(dx), abs(dy)),
                       min(dx >= 0 ? sourceImage.size.width - mark.start.x : mark.start.x,
                           dy >= 0 ? sourceImage.size.height - mark.start.y : mark.start.y))
        return CGPoint(x: mark.start.x + (dx >= 0 ? side : -side),
                       y: mark.start.y + (dy >= 0 ? side : -side))
    }

    private func viewPoint(_ imagePoint: CGPoint, in rect: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + imagePoint.x * scale,
                y: rect.minY + imagePoint.y * scale)
    }

    private func draw(_ mark: Mark, in rect: CGRect, scale: CGFloat) {
        let start = viewPoint(mark.start, in: rect, scale: scale)
        let end = viewPoint(mark.end, in: rect, scale: scale)
        let lineWidth = max(1, mark.lineWidth * scale)
        mark.color.setStroke()
        mark.color.setFill()

        if mark.tool == .arrow {
            drawArrow(from: start, to: end, lineWidth: lineWidth, color: mark.color)
            return
        }

        let path: NSBezierPath
        switch mark.tool {
        case .rectangle:
            path = NSBezierPath(rect: CGRect(x: min(start.x, end.x),
                                             y: min(start.y, end.y),
                                             width: abs(end.x - start.x),
                                             height: abs(end.y - start.y)))
        case .ellipse:
            path = NSBezierPath(ovalIn: CGRect(x: min(start.x, end.x),
                                               y: min(start.y, end.y),
                                               width: abs(end.x - start.x),
                                               height: abs(end.y - start.y)))
        case .arrow:
            path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
        case .pen:
            path = NSBezierPath()
            if let first = mark.points.first {
                path.move(to: viewPoint(first, in: rect, scale: scale))
                for point in mark.points.dropFirst() {
                    path.line(to: viewPoint(point, in: rect, scale: scale))
                }
            }
        }

        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat, color: NSColor) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }

        let ux = dx / length
        let uy = dy / length
        let perpendicular = CGPoint(x: -uy, y: ux)
        let idealHeadLength = max(18, lineWidth * 4.8)
        let headLength = min(idealHeadLength, max(lineWidth * 2.4, length * 0.34))
        let headHalfWidth = headLength * 0.62
        let base = CGPoint(x: end.x - ux * headLength,
                           y: end.y - uy * headLength)
        let left = CGPoint(x: base.x + perpendicular.x * headHalfWidth,
                           y: base.y + perpendicular.y * headHalfWidth)
        let right = CGPoint(x: base.x - perpendicular.x * headHalfWidth,
                            y: base.y - perpendicular.y * headHalfWidth)

        color.setStroke()

        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: CGPoint(x: end.x - ux * lineWidth * 0.35,
                               y: end.y - uy * lineWidth * 0.35))
        shaft.lineWidth = lineWidth
        shaft.lineCapStyle = .round
        shaft.stroke()

        let chevron = NSBezierPath()
        chevron.move(to: left)
        chevron.line(to: end)
        chevron.line(to: right)
        chevron.lineWidth = lineWidth * 1.08
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.stroke()
    }
}

final class EditorWindow: NSWindow {
    weak var editorController: EditorWindowController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if modifiers.contains(.command) {
            switch key {
            case "z" where modifiers.contains(.shift): editorController?.redo(nil); return true
            case "z": editorController?.undo(nil); return true
            case "c": editorController?.copyImage(nil); return true
            case "s": editorController?.saveImage(nil); return true
            default: break
            }
        } else if modifiers.isEmpty {
            switch key {
            case "r": editorController?.selectTool(.rectangle); return true
            case "o": editorController?.selectTool(.ellipse); return true
            case "a": editorController?.selectTool(.arrow); return true
            case "p": editorController?.selectTool(.pen); return true
            case "\u{1b}": close(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: AnnotationCanvas
    private let sourceURL: URL?
    private let ownsSourceFile: Bool
    private let onClose: (EditorWindowController) -> Void

    private let toolsControl: NSSegmentedControl
    private let colorWell = NSColorWell()
    private let widthSlider = NSSlider(value: 4, minValue: 1, maxValue: 12, target: nil, action: nil)
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "拖动鼠标开始标注")
    private var statusResetWorkItem: DispatchWorkItem?

    init(image: NSImage,
         sourceURL: URL?,
         ownsSourceFile: Bool,
         onClose: @escaping (EditorWindowController) -> Void) {
        self.canvas = AnnotationCanvas(image: image)
        self.sourceURL = sourceURL
        self.ownsSourceFile = ownsSourceFile
        self.onClose = onClose

        let symbols = MarkTool.allCases.map {
            NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: $0.title) ?? NSImage()
        }
        self.toolsControl = NSSegmentedControl(images: symbols,
                                               trackingMode: .selectOne,
                                               target: nil,
                                               action: nil)

        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let maxSize = CGSize(width: min(1180, visibleFrame.width * 0.88),
                             height: min(820, visibleFrame.height * 0.88))
        let aspect = max(image.size.width / max(image.size.height, 1), 0.25)
        var contentSize = CGSize(width: maxSize.width, height: min(maxSize.height, maxSize.width / aspect + 70))
        if contentSize.height < 560 { contentSize.height = 560 }
        if contentSize.height > maxSize.height {
            contentSize.height = maxSize.height
            contentSize.width = min(maxSize.width, (contentSize.height - 70) * aspect)
        }
        contentSize.width = min(maxSize.width, max(contentSize.width, 900))

        let editorWindow = EditorWindow(contentRect: CGRect(origin: .zero, size: contentSize),
                                        styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                        backing: .buffered,
                                        defer: false)
        editorWindow.title = "轻截 · 标注"
        editorWindow.minSize = CGSize(width: min(900, maxSize.width), height: 520)
        editorWindow.isReleasedWhenClosed = false
        editorWindow.titlebarSeparatorStyle = .none

        super.init(window: editorWindow)
        editorWindow.editorController = self
        editorWindow.delegate = self
        configureInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureInterface() {
        guard let window else { return }
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let toolbar = NSVisualEffectView()
        toolbar.material = .headerView
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        canvas.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(canvas)
        root.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 64),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        toolsControl.selectedSegment = MarkTool.arrow.rawValue
        toolsControl.segmentStyle = .rounded
        toolsControl.target = self
        toolsControl.action = #selector(toolChanged(_:))
        toolsControl.toolTip = "矩形 R · 圆形 O · 箭头 A · 画笔 P"
        for index in 0..<MarkTool.allCases.count {
            toolsControl.setWidth(38, forSegment: index)
            toolsControl.setToolTip(MarkTool.allCases[index].title, forSegment: index)
        }

        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.toolTip = "标注颜色"
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 42).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 28).isActive = true

        widthSlider.numberOfTickMarks = 4
        widthSlider.allowsTickMarkValuesOnly = false
        widthSlider.target = self
        widthSlider.action = #selector(widthChanged(_:))
        widthSlider.toolTip = "线条粗细"
        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        widthSlider.widthAnchor.constraint(equalToConstant: 94).isActive = true

        configureIconButton(undoButton, symbol: "arrow.uturn.backward", tooltip: "撤销 ⌘Z", action: #selector(undo(_:)))
        configureIconButton(redoButton, symbol: "arrow.uturn.forward", tooltip: "重做 ⇧⌘Z", action: #selector(redo(_:)))

        let clearButton = NSButton(title: "清除", target: self, action: #selector(clearMarks(_:)))
        clearButton.bezelStyle = .rounded
        clearButton.toolTip = "清除全部标注"

        let copyButton = NSButton(title: "复制", target: self, action: #selector(copyImage(_:)))
        copyButton.bezelStyle = .rounded
        copyButton.toolTip = "复制成品图 ⌘C"

        let saveButton = NSButton(title: "保存…", target: self, action: #selector(saveImage(_:)))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.toolTip = "保存 PNG ⌘S"

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingTail

        let thicknessIcon = NSImageView(image: NSImage(systemSymbolName: "lineweight", accessibilityDescription: "粗细") ?? NSImage())
        thicknessIcon.contentTintColor = .secondaryLabelColor

        let leadingStack = NSStackView(views: [toolsControl, separator(), colorWell, thicknessIcon, widthSlider])
        leadingStack.orientation = .horizontal
        leadingStack.alignment = .centerY
        leadingStack.spacing = 10

        let trailingStack = NSStackView(views: [undoButton, redoButton, clearButton, separator(), copyButton, saveButton])
        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 8

        let row = NSStackView(views: [leadingStack, statusLabel, trailingStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -18),
            row.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor)
        ])

        canvas.onHistoryChange = { [weak self] in self?.updateHistoryButtons() }
        updateHistoryButtons()
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return box
    }

    private func configureIconButton(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.toolTip = tooltip
    }

    func selectTool(_ tool: MarkTool) {
        toolsControl.selectedSegment = tool.rawValue
        canvas.selectedTool = tool
        showStatus("\(tool.title)工具")
    }

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        guard let tool = MarkTool(rawValue: sender.selectedSegment) else { return }
        selectTool(tool)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        canvas.selectedColor = sender.color
        showStatus("颜色已更新")
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        canvas.selectedLineWidth = CGFloat(sender.doubleValue)
    }

    @objc func undo(_ sender: Any?) {
        canvas.undo()
    }

    @objc func redo(_ sender: Any?) {
        canvas.redo()
    }

    @objc private func clearMarks(_ sender: Any?) {
        canvas.removeAllMarks()
        showStatus("已清除标注")
    }

    @objc func copyImage(_ sender: Any?) {
        guard let data = canvas.flattenedPNG(),
              let image = NSImage(data: data) else {
            showStatus("复制失败")
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        showStatus("已复制到剪贴板")
    }

    @objc func saveImage(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.title = "保存标注截图"
        panel.nameFieldStringValue = "轻截-\(Self.timestamp()).png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            guard let data = self?.canvas.flattenedPNG() else {
                self?.showStatus("保存失败")
                return
            }
            do {
                try data.write(to: destination, options: .atomic)
                self?.showStatus("已保存")
            } catch {
                self?.showError(title: "保存失败", message: error.localizedDescription)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if ownsSourceFile, let sourceURL {
            try? FileManager.default.removeItem(at: sourceURL)
        }
        onClose(self)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateHistoryButtons() {
        undoButton.isEnabled = !canvas.marks.isEmpty
        redoButton.isEnabled = !canvas.redoMarks.isEmpty
    }

    private func showStatus(_ text: String) {
        statusResetWorkItem?.cancel()
        statusLabel.stringValue = text
        let workItem = DispatchWorkItem { [weak self] in
            self?.statusLabel.stringValue = "拖动鼠标开始标注"
        }
        statusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    private func showError(title: String, message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var regionHotKey: EventHotKeyRef?
    private var fullScreenHotKey: EventHotKeyRef?
    private var statusItemHotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var isCapturing = false
    private var editors: [EditorWindowController] = []
    private var recordingSourceController: RecordingSourceWindowController?
    private var recordingStatusController: RecordingStatusController?
    private var hasShownPermissionGuideThisLaunch = false
    @available(macOS 15.0, *)
    private lazy var recordingManager = RecordingManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        registerGlobalHotKeys()

        let arguments = CommandLine.arguments
        if arguments.contains("--test-status-item-cycle") {
            setStatusItemHidden(true)
            let hiddenPass = !statusItem.isVisible && UserDefaults.standard.bool(forKey: "StatusItemHidden")
            setStatusItemHidden(false)
            let shownPass = statusItem.isVisible && !UserDefaults.standard.bool(forKey: "StatusItemHidden")
            let result = hiddenPass && shownPass ? "PASS" : "FAIL"
            FileHandle.standardOutput.write(Data("STATUS_ITEM_CYCLE_\(result)\n".utf8))
            NSApp.terminate(nil)
            return
        }
        let argumentImagePath: String? = {
            guard let index = arguments.firstIndex(of: "--test-image"),
                  arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }()
        let testImagePath = argumentImagePath ?? ProcessInfo.processInfo.environment["QUICKMARK_TEST_IMAGE"]
        if let testImagePath, !testImagePath.isEmpty {
            NSApp.setActivationPolicy(.regular)
            openEditor(at: URL(fileURLWithPath: testImagePath), ownsSourceFile: false)
        }
        if arguments.contains("--test-capture-fullscreen") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.captureFullScreen(nil)
            }
        }
        if arguments.contains("--test-recording-ui") {
            NSApp.setActivationPolicy(.regular)
            let controller = RecordingSourceWindowController { _ in }
            recordingSourceController = controller
            controller.showWindow(nil)
        }
        if arguments.contains("--test-recording-status-ui") {
            NSApp.setActivationPolicy(.regular)
            let status = RecordingStatusController()
            recordingStatusController = status
            status.onStop = { [weak self] in self?.stopActiveRecording() }
            status.showPreparing()
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "轻截")
            button.image?.isTemplate = true
            button.toolTip = "轻截"
        }

        let menu = NSMenu()
        let region = NSMenuItem(title: "截取区域", action: #selector(captureRegion(_:)), keyEquivalent: "2")
        region.keyEquivalentModifierMask = [.command, .shift]
        region.target = self
        menu.addItem(region)

        let full = NSMenuItem(title: "截取主屏幕", action: #selector(captureFullScreen(_:)), keyEquivalent: "1")
        full.keyEquivalentModifierMask = [.command, .shift]
        full.target = self
        menu.addItem(full)

        let open = NSMenuItem(title: "打开图片标注…", action: #selector(openImage(_:)), keyEquivalent: "o")
        open.keyEquivalentModifierMask = [.command]
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        let record = NSMenuItem(title: "开始录屏…", action: #selector(showRecordingSources(_:)), keyEquivalent: "5")
        record.keyEquivalentModifierMask = [.command, .shift]
        record.target = self
        menu.addItem(record)

        let recordings = NSMenuItem(title: "打开录屏文件夹", action: #selector(openRecordingsFolder(_:)), keyEquivalent: "")
        recordings.target = self
        menu.addItem(recordings)

        menu.addItem(.separator())
        let hideStatusItem = NSMenuItem(title: "隐藏菜单栏图标（⌘⇧0 可恢复）",
                                        action: #selector(hideStatusItem(_:)),
                                        keyEquivalent: "")
        hideStatusItem.target = self
        menu.addItem(hideStatusItem)

        menu.addItem(.separator())
        let help = NSMenuItem(title: "快捷键：R 矩形 · O 圆形 · A 箭头 · P 画笔", action: nil, keyEquivalent: "")
        help.isEnabled = false
        menu.addItem(help)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出轻截", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        applySavedStatusItemVisibility()
    }

    private func registerGlobalHotKeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                switch hotKeyID.id {
                case 1: delegate.captureRegion(nil)
                case 2: delegate.captureFullScreen(nil)
                case 3: delegate.toggleStatusItemVisibility()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)

        let signature = OSType(0x514D5348) // QMSH
        let regionID = EventHotKeyID(signature: signature, id: 1)
        let fullID = EventHotKeyID(signature: signature, id: 2)
        let statusItemID = EventHotKeyID(signature: signature, id: 3)
        let modifiers = UInt32(cmdKey | shiftKey)
        let regionStatus = RegisterEventHotKey(UInt32(kVK_ANSI_2), modifiers, regionID,
                                                GetApplicationEventTarget(), 0, &regionHotKey)
        let fullStatus = RegisterEventHotKey(UInt32(kVK_ANSI_1), modifiers, fullID,
                                             GetApplicationEventTarget(), 0, &fullScreenHotKey)
        let statusItemStatus = RegisterEventHotKey(UInt32(kVK_ANSI_0), modifiers, statusItemID,
                                                   GetApplicationEventTarget(), 0, &statusItemHotKey)
        if regionStatus != noErr || fullStatus != noErr || statusItemStatus != noErr {
            FileHandle.standardError.write(Data("QuickMarkShot: hotkey registration failed (region=\(regionStatus), full=\(fullStatus), status=\(statusItemStatus))\n".utf8))
        }
    }

    @objc private func hideStatusItem(_ sender: Any?) {
        setStatusItemHidden(true)
    }

    private func toggleStatusItemVisibility() {
        setStatusItemHidden(statusItem.isVisible)
    }

    private func applySavedStatusItemVisibility() {
        let hidden = UserDefaults.standard.bool(forKey: "StatusItemHidden")
        statusItem.isVisible = !hidden
        reportStatusItemVisibility()
    }

    private func setStatusItemHidden(_ hidden: Bool) {
        UserDefaults.standard.set(hidden, forKey: "StatusItemHidden")
        statusItem.isVisible = !hidden
        reportStatusItemVisibility()
    }

    private func reportStatusItemVisibility() {
        let hidden = !statusItem.isVisible
        FileHandle.standardError.write(Data("QuickMarkShot: status item hidden=\(hidden) visible=\(statusItem.isVisible)\n".utf8))
    }

    @objc private func captureRegion(_ sender: Any?) {
        capture(arguments: ["-i", "-x"])
    }

    @objc private func captureFullScreen(_ sender: Any?) {
        capture(arguments: ["-m", "-x"])
    }

    private func capture(arguments: [String]) {
        guard !isCapturing else { return }

        guard ensureScreenCaptureAccess() else { return }

        isCapturing = true

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuickMarkShot", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("capture-\(UUID().uuidString).png")

        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments + [file.path]
        process.standardError = errors
        process.terminationHandler = { [weak self] process in
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCapturing = false
                if FileManager.default.fileExists(atPath: file.path) {
                    self.openEditor(at: file, ownsSourceFile: true)
                } else if !errorText.isEmpty {
                    self.showCaptureError(errorText)
                }
            }
        }

        do {
            try process.run()
        } catch {
            isCapturing = false
            showCaptureError(error.localizedDescription)
        }
    }

    @objc private func openImage(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "选择要标注的图片"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            openEditor(at: url, ownsSourceFile: false)
        }
    }

    @objc private func showRecordingSources(_ sender: Any?) {
        guard ensureScreenCaptureAccess() else { return }
        guard #available(macOS 15.0, *) else {
            showCaptureError(RecordingError.unsupportedSystem.localizedDescription)
            return
        }
        if recordingManager.isRecording {
            recordingStatusController?.window?.orderFrontRegardless()
            return
        }
        let controller = RecordingSourceWindowController { [weak self] request in
            self?.beginRecording(request)
        }
        recordingSourceController = controller
        controller.showWindow(nil)
    }

    @available(macOS 15.0, *)
    private func beginRecording(_ request: RecordingRequest) {
        let status = RecordingStatusController()
        recordingStatusController = status
        status.onStop = { [weak self] in self?.stopActiveRecording() }
        status.showPreparing()
        recordingManager.start(request: request, started: { [weak status] in
            status?.markStarted()
        }, finished: { [weak self, weak status] url in
            status?.dismiss()
            self?.recordingStatusController = nil
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }, failed: { [weak self, weak status] error in
            status?.dismiss()
            self?.recordingStatusController = nil
            self?.showCaptureError(error.localizedDescription)
        })
    }

    private func stopActiveRecording() {
        recordingStatusController?.dismiss()
        recordingStatusController = nil
        openRecordingsDirectory()
        if #available(macOS 15.0, *) {
            recordingManager.stop()
        }
    }

    @objc private func openRecordingsFolder(_ sender: Any?) {
        openRecordingsDirectory()
    }

    private func openRecordingsDirectory() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("轻截录屏", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private func openEditor(at url: URL, ownsSourceFile: Bool) {
        guard let image = NSImage(contentsOf: url), image.isValid else {
            showCaptureError("无法读取图片。")
            return
        }
        let editor = EditorWindowController(image: image,
                                            sourceURL: url,
                                            ownsSourceFile: ownsSourceFile) { [weak self] closing in
            self?.editors.removeAll { $0 === closing }
        }
        editors.append(editor)
        editor.showWindow(nil)
    }

    private func showCaptureError(_ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "无法完成截图"
        alert.informativeText = "请在“系统设置 → 隐私与安全性 → 屏幕与系统录音”中允许轻截，然后重试。\n\n\(detail)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func showPermissionGuide() {
        guard !hasShownPermissionGuideThisLaunch else { return }
        hasShownPermissionGuideThisLaunch = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请允许“轻截”访问屏幕内容。授权后重新打开轻截，即可使用区域和主屏幕截图。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            hasShownPermissionGuideThisLaunch = false
            return true
        }

        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let requestKey = "ScreenCapturePermissionRequestedBuild-\(build)"
        if !UserDefaults.standard.bool(forKey: requestKey) {
            UserDefaults.standard.set(true, forKey: requestKey)
            if CGRequestScreenCaptureAccess() {
                return true
            }
        }

        showPermissionGuide()
        return false
    }
}
