import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import ScreenCaptureKit

enum RecordingMode: Int, CaseIterable {
    case display
    case region
    case window
    case application

    var title: String {
        switch self {
        case .display: return "全屏"
        case .region: return "区域"
        case .window: return "窗口"
        case .application: return "应用"
        }
    }
}

struct RecordingRequest {
    let mode: RecordingMode
    let display: SCDisplay?
    let window: SCWindow?
    let application: SCRunningApplication?
    let region: CGRect?
    let capturesAudio: Bool
    let showsCursor: Bool
    let followsCursor: Bool
    let zoomAmount: CGFloat
    let excludedApplications: [SCRunningApplication]
    let trackingRect: CGRect
}

final class RegionSelectionView: NSView {
    var onComplete: ((CGRect?) -> Void)?
    private var startPoint: CGPoint?
    private var selection: CGRect = .zero

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.30).setFill()
        bounds.fill()

        if !selection.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            selection.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.systemRed.setStroke()
            let outline = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 2
            outline.stroke()

            let sizeText = "\(Int(selection.width)) × \(Int(selection.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.72)
            ]
            let textSize = sizeText.size(withAttributes: attributes)
            let point = CGPoint(x: selection.minX,
                                y: max(8, selection.minY - textSize.height - 9))
            sizeText.draw(at: point, withAttributes: attributes)
        }

        let instruction = "拖动框选录制区域  ·  Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.68)
        ]
        let size = instruction.size(withAttributes: attributes)
        instruction.draw(at: CGPoint(x: bounds.midX - size.width / 2,
                                     y: bounds.maxY - size.height - 36),
                         withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(startPoint.x, point.x),
                           y: min(startPoint.y, point.y),
                           width: abs(point.x - startPoint.x),
                           height: abs(point.y - startPoint.y)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard selection.width >= 24, selection.height >= 24 else {
            startPoint = nil
            selection = .zero
            needsDisplay = true
            return
        }
        onComplete?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onComplete?(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

final class RegionSelectionController: NSWindowController {
    private let onComplete: (CGRect?) -> Void

    init(screen: NSScreen, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        let panel = NSPanel(contentRect: screen.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false,
                            screen: screen)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        panel.contentView = view
        super.init(window: panel)

        view.onComplete = { [weak self] rect in
            guard let self else { return }
            self.window?.orderOut(nil)
            self.onComplete(rect)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func begin() {
        guard let window, let view = window.contentView else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class RecordingSourceWindowController: NSWindowController {
    private let onStart: (RecordingRequest) -> Void
    private var content: SCShareableContent?
    private var displays: [SCDisplay] = []
    private var windows: [SCWindow] = []
    private var applications: [SCRunningApplication] = []
    private var applicationIconCache: [pid_t: NSImage] = [:]
    private var selectedRegion: CGRect?
    private var regionSelector: RegionSelectionController?

    private let modeControl = NSSegmentedControl(labels: RecordingMode.allCases.map(\.title),
                                                  trackingMode: .selectOne,
                                                  target: nil,
                                                  action: nil)
    private let sourcePopup = NSPopUpButton()
    private let selectRegionButton = NSButton(title: "框选区域…", target: nil, action: nil)
    private let regionLabel = NSTextField(labelWithString: "尚未选择区域")
    private let audioCheck = NSButton(checkboxWithTitle: "录制系统声音", target: nil, action: nil)
    private let cursorCheck = NSButton(checkboxWithTitle: "显示鼠标指针", target: nil, action: nil)
    private let zoomCheck = NSButton(checkboxWithTitle: "鼠标跟随放大", target: nil, action: nil)
    private let zoomPopup = NSPopUpButton()
    private let progress = NSProgressIndicator()
    private let messageLabel = NSTextField(labelWithString: "正在读取可录制内容…")
    private let startButton = NSButton(title: "开始录制", target: nil, action: nil)

    init(onStart: @escaping (RecordingRequest) -> Void) {
        self.onStart = onStart
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 318),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "开始录屏"
        window.isReleasedWhenClosed = false
        window.titlebarSeparatorStyle = .none
        super.init(window: window)
        configureInterface()
        loadContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureInterface() {
        guard let window else { return }
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root

        let title = NSTextField(labelWithString: "选择录制内容")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "轻截只会录制你选中的画面")
        subtitle.textColor = .secondaryLabelColor

        modeControl.selectedSegment = RecordingMode.display.rawValue
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.segmentStyle = .rounded

        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged(_:))
        sourcePopup.isEnabled = false

        selectRegionButton.target = self
        selectRegionButton.action = #selector(selectRegion(_:))
        selectRegionButton.bezelStyle = .rounded
        selectRegionButton.isHidden = true

        regionLabel.textColor = .secondaryLabelColor
        regionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        regionLabel.isHidden = true

        audioCheck.state = .on
        cursorCheck.state = .on
        zoomCheck.state = .on
        zoomPopup.addItems(withTitles: ["1.5×", "1.8×", "2.0×"])
        zoomPopup.selectItem(at: 1)
        zoomPopup.controlSize = .small

        progress.style = .spinning
        progress.controlSize = .small
        progress.startAnimation(nil)

        messageLabel.textColor = .secondaryLabelColor
        messageLabel.font = .systemFont(ofSize: 12)

        let loadingRow = NSStackView(views: [progress, messageLabel])
        loadingRow.orientation = .horizontal
        loadingRow.alignment = .centerY
        loadingRow.spacing = 8

        let zoomRow = NSStackView(views: [zoomCheck, zoomPopup])
        zoomRow.orientation = .horizontal
        zoomRow.spacing = 8

        let options = NSStackView(views: [audioCheck, cursorCheck, zoomRow])
        options.orientation = .horizontal
        options.spacing = 20

        startButton.target = self
        startButton.action = #selector(startRecording(_:))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.isEnabled = false

        let cancelButton = NSButton(title: "取消", target: window, action: #selector(NSWindow.close))
        cancelButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [cancelButton, startButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let sourceRow = NSStackView(views: [sourcePopup, selectRegionButton])
        sourceRow.orientation = .horizontal
        sourceRow.alignment = .centerY
        sourceRow.spacing = 10
        sourcePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let contentStack = NSStackView(views: [title, subtitle, modeControl, sourceRow, regionLabel, options, loadingRow])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 13
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        modeControl.widthAnchor.constraint(equalToConstant: 330).isActive = true
        sourceRow.widthAnchor.constraint(equalToConstant: 470).isActive = true

        root.addSubview(contentStack)
        root.addSubview(buttons)
        buttons.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 25),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -25),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
    }

    private func loadContent() {
        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                    onScreenWindowsOnly: true)
                await MainActor.run {
                    self?.apply(content)
                }
            } catch {
                await MainActor.run {
                    self?.showLoadError(error)
                }
            }
        }
    }

    private func apply(_ content: SCShareableContent) {
        self.content = content
        displays = content.displays
        windows = content.windows.filter { window in
            guard window.isOnScreen,
                  window.windowLayer == 0,
                  window.frame.width >= 80,
                  window.frame.height >= 60,
                  let app = window.owningApplication else { return false }
            return app.bundleIdentifier != Bundle.main.bundleIdentifier
        }.sorted {
            let lhs = "\($0.owningApplication?.applicationName ?? "") \($0.title ?? "")"
            let rhs = "\($1.owningApplication?.applicationName ?? "") \($1.title ?? "")"
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        let visibleProcessIDs = Set(windows.compactMap { $0.owningApplication?.processID })
        applications = content.applications.filter {
            $0.bundleIdentifier != Bundle.main.bundleIdentifier && visibleProcessIDs.contains($0.processID)
        }.sorted { $0.applicationName.localizedStandardCompare($1.applicationName) == .orderedAscending }

        progress.stopAnimation(nil)
        progress.isHidden = true
        messageLabel.stringValue = "选择完成后即可开始"
        sourcePopup.isEnabled = true
        refreshSources()
    }

    private func showLoadError(_ error: Error) {
        progress.stopAnimation(nil)
        progress.isHidden = true
        messageLabel.stringValue = "无法读取屏幕内容：\(error.localizedDescription)"
        startButton.isEnabled = false
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        selectedRegion = nil
        refreshSources()
    }

    @objc private func sourceChanged(_ sender: NSPopUpButton) {
        selectedRegion = nil
        refreshRegionState()
    }

    private func refreshSources() {
        guard let mode = RecordingMode(rawValue: modeControl.selectedSegment) else { return }
        sourcePopup.removeAllItems()

        switch mode {
        case .display, .region:
            for (index, display) in displays.enumerated() {
                sourcePopup.addItem(withTitle: "显示器 \(index + 1) · \(display.width)×\(display.height)")
                sourcePopup.lastItem?.image = sourceIcon(systemName: "display")
            }
        case .window:
            for window in windows {
                let app = window.owningApplication?.applicationName ?? "应用"
                let title = (window.title?.isEmpty == false) ? window.title! : "未命名窗口"
                sourcePopup.addItem(withTitle: "\(app) · \(title)")
                sourcePopup.lastItem?.image = applicationIcon(for: window.owningApplication)
            }
        case .application:
            for application in applications {
                sourcePopup.addItem(withTitle: application.applicationName)
                sourcePopup.lastItem?.image = applicationIcon(for: application)
            }
        }

        selectRegionButton.isHidden = mode != .region
        regionLabel.isHidden = mode != .region
        refreshRegionState()
    }

    private func refreshRegionState() {
        guard let mode = RecordingMode(rawValue: modeControl.selectedSegment) else { return }
        let hasSource = sourcePopup.numberOfItems > 0
        if mode == .region {
            if let selectedRegion {
                regionLabel.stringValue = "已选择 \(Int(selectedRegion.width)) × \(Int(selectedRegion.height))"
            } else {
                regionLabel.stringValue = "尚未选择区域"
            }
            startButton.isEnabled = hasSource && selectedRegion != nil
        } else {
            startButton.isEnabled = hasSource
        }
    }

    @objc private func selectRegion(_ sender: Any?) {
        guard displays.indices.contains(sourcePopup.indexOfSelectedItem),
              let screen = screen(for: displays[sourcePopup.indexOfSelectedItem]) else { return }

        window?.orderOut(nil)
        let selector = RegionSelectionController(screen: screen) { [weak self] rect in
            guard let self else { return }
            self.regionSelector = nil
            if let rect {
                self.selectedRegion = CGRect(x: rect.minX,
                                             y: screen.frame.height - rect.maxY,
                                             width: rect.width,
                                             height: rect.height)
            }
            self.refreshRegionState()
            self.showWindow(nil)
        }
        regionSelector = selector
        selector.begin()
    }

    @objc private func startRecording(_ sender: Any?) {
        guard let mode = RecordingMode(rawValue: modeControl.selectedSegment) else { return }
        let index = sourcePopup.indexOfSelectedItem

        var display: SCDisplay?
        var window: SCWindow?
        var application: SCRunningApplication?
        var trackingRect: CGRect = .zero

        switch mode {
        case .display, .region:
            guard displays.indices.contains(index) else { return }
            display = displays[index]
            trackingRect = display!.frame
            if mode == .region, let region = selectedRegion {
                trackingRect = CGRect(x: display!.frame.minX + region.minX,
                                      y: display!.frame.minY + region.minY,
                                      width: region.width,
                                      height: region.height)
            }
        case .window:
            guard windows.indices.contains(index) else { return }
            window = windows[index]
            display = bestDisplay(for: window!.frame)
            trackingRect = window!.frame
        case .application:
            guard applications.indices.contains(index) else { return }
            application = applications[index]
            let appWindows = windows.filter { $0.owningApplication?.processID == application?.processID }
            trackingRect = appWindows.map(\.frame).reduce(.null) { $0.union($1) }
            display = bestDisplay(for: trackingRect) ?? displays.first
            if trackingRect.isNull { trackingRect = display?.frame ?? .zero }
        }

        let request = RecordingRequest(mode: mode,
                                       display: display,
                                       window: window,
                                       application: application,
                                       region: selectedRegion,
                                       capturesAudio: audioCheck.state == .on,
                                       showsCursor: cursorCheck.state == .on,
                                       followsCursor: zoomCheck.state == .on,
                                       zoomAmount: [1.5, 1.8, 2.0][max(0, zoomPopup.indexOfSelectedItem)],
                                       excludedApplications: content?.applications.filter {
                                           $0.bundleIdentifier == Bundle.main.bundleIdentifier
                                       } ?? [],
                                       trackingRect: trackingRect)
        close()
        onStart(request)
    }

    private func screen(for display: SCDisplay) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        }
    }

    private func bestDisplay(for rect: CGRect) -> SCDisplay? {
        displays.max { first, second in
            first.frame.intersection(rect).area < second.frame.intersection(rect).area
        }
    }

    private func applicationIcon(for application: SCRunningApplication?) -> NSImage? {
        guard let application else { return sourceIcon(systemName: "app.fill") }
        if let cached = applicationIconCache[application.processID] { return cached }

        let image: NSImage
        if let bundleURL = NSRunningApplication(processIdentifier: application.processID)?.bundleURL {
            image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        } else {
            image = sourceIcon(systemName: "app.fill") ?? NSImage(size: NSSize(width: 16, height: 16))
        }
        image.size = NSSize(width: 16, height: 16)
        applicationIconCache[application.processID] = image
        return image
    }

    private func sourceIcon(systemName: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }
}

private extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}

final class RecordingStatusController: NSWindowController {
    private let timerLabel = NSTextField(labelWithString: "00:00")
    private let stateLabel = NSTextField(labelWithString: "正在准备…")
    private var timer: Timer?
    private var startDate: Date?
    var onStop: (() -> Void)?

    init() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 250, height: 58),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        configureInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureInterface() {
        guard let window else { return }
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        window.contentView = effect

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10)
        ])

        timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        timerLabel.textColor = .labelColor
        stateLabel.font = .systemFont(ofSize: 11)
        stateLabel.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [timerLabel, stateLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let stopButton = NSButton(title: "停止", target: self, action: #selector(stop(_:)))
        stopButton.bezelStyle = .rounded

        let row = NSStackView(views: [dot, labels, stopButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 11
        row.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 15),
            row.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])
    }

    func showPreparing() {
        startDate = nil
        timerLabel.stringValue = "00:00"
        stateLabel.stringValue = "正在准备…"
        positionAndShow()
    }

    func markStarted() {
        startDate = Date()
        stateLabel.stringValue = "正在录制"
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }

    func markFinishing() {
        stateLabel.stringValue = "正在保存…"
        timer?.invalidate()
        timer = nil
    }

    func finish(message: String) {
        timer?.invalidate()
        timer = nil
        stateLabel.stringValue = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
    }

    @objc private func stop(_ sender: Any?) {
        onStop?()
    }

    private func updateTime() {
        guard let startDate else { return }
        let seconds = Int(Date().timeIntervalSince(startDate))
        timerLabel.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func positionAndShow() {
        guard let window else { return }
        let visible = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        window.setFrameOrigin(CGPoint(x: visible.maxX - window.frame.width - 20,
                                      y: visible.maxY - window.frame.height - 20))
        window.orderFrontRegardless()
    }
}

@available(macOS 15.0, *)
final class RecordingManager: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    private(set) var isRecording = false
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var rawOutputURL: URL?
    private var recordingRequest: RecordingRequest?
    private var cursorTracker: CursorTracker?
    private var startedCallback: (() -> Void)?
    private var finishedCallback: ((URL) -> Void)?
    private var errorCallback: ((Error) -> Void)?
    private var didComplete = false

    var recordingsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("轻截录屏", isDirectory: true)
    }

    func start(request: RecordingRequest,
               started: @escaping () -> Void,
               finished: @escaping (URL) -> Void,
               failed: @escaping (Error) -> Void) {
        guard !isRecording else { return }
        startedCallback = started
        finishedCallback = finished
        errorCallback = failed
        didComplete = false

        do {
            try FileManager.default.createDirectory(at: recordingsDirectory,
                                                    withIntermediateDirectories: true)
            let url = recordingsDirectory.appendingPathComponent("轻截录屏-\(Self.timestamp()).mp4")
            let rawURL = request.followsCursor
                ? FileManager.default.temporaryDirectory.appendingPathComponent("QuickMarkShot-raw-\(UUID().uuidString).mp4")
                : url
            let filter = try makeFilter(for: request)
            let configuration = makeConfiguration(for: request)

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            let outputConfiguration = SCRecordingOutputConfiguration()
            outputConfiguration.outputURL = rawURL
            outputConfiguration.outputFileType = .mp4
            outputConfiguration.videoCodecType = .h264
            let recordingOutput = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
            try stream.addRecordingOutput(recordingOutput)

            self.stream = stream
            self.recordingOutput = recordingOutput
            self.outputURL = url
            self.rawOutputURL = rawURL
            self.recordingRequest = request
            self.isRecording = true
            stream.startCapture { [weak self] error in
                if let error {
                    self?.completeWithError(error)
                }
            }
        } catch {
            completeWithError(error)
        }
    }

    func stop() {
        guard isRecording, let stream else { return }
        stream.stopCapture { [weak self] error in
            if let error {
                self?.completeWithError(error)
            }
        }
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let request = self.recordingRequest, request.followsCursor {
                let tracker = CursorTracker()
                tracker.start(in: request.trackingRect)
                self.cursorTracker = tracker
            }
            self.startedCallback?()
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didComplete,
                  let outputURL = self.outputURL,
                  let rawOutputURL = self.rawOutputURL else { return }
            self.isRecording = false
            self.stream = nil
            self.recordingOutput = nil
            let samples = self.cursorTracker?.stop() ?? []
            self.cursorTracker = nil
            if let request = self.recordingRequest, request.followsCursor {
                MouseZoomProcessor.process(inputURL: rawOutputURL,
                                           outputURL: outputURL,
                                           samples: samples,
                                           zoomAmount: request.zoomAmount) { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self, !self.didComplete else { return }
                        self.didComplete = true
                        switch result {
                        case .success:
                            try? FileManager.default.removeItem(at: rawOutputURL)
                            self.finishedCallback?(outputURL)
                        case .failure(let error):
                            self.errorCallback?(error)
                        }
                        self.clearCallbacks()
                    }
                }
            } else {
                self.didComplete = true
                self.finishedCallback?(outputURL)
                self.clearCallbacks()
            }
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        completeWithError(error)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        completeWithError(error)
    }

    private func makeFilter(for request: RecordingRequest) throws -> SCContentFilter {
        switch request.mode {
        case .window:
            guard let window = request.window else { throw RecordingError.missingSource }
            return SCContentFilter(desktopIndependentWindow: window)
        case .application:
            guard let display = request.display, let application = request.application else {
                throw RecordingError.missingSource
            }
            return SCContentFilter(display: display,
                                   including: [application],
                                   exceptingWindows: [])
        case .display, .region:
            guard let display = request.display else { throw RecordingError.missingSource }
            return SCContentFilter(display: display,
                                   excludingApplications: request.excludedApplications,
                                   exceptingWindows: [])
        }
    }

    private func makeConfiguration(for request: RecordingRequest) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 8
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = request.showsCursor
        configuration.showMouseClicks = request.showsCursor
        configuration.capturesAudio = request.capturesAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.scalesToFit = true

        let pointSize: CGSize
        let scale: CGFloat
        switch request.mode {
        case .window:
            pointSize = request.window?.frame.size ?? CGSize(width: 1280, height: 720)
            scale = screenScale(for: request.display)
        case .region:
            let region = request.region ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
            configuration.sourceRect = region
            pointSize = region.size
            scale = screenScale(for: request.display)
        case .display, .application:
            pointSize = CGSize(width: request.display?.width ?? 1920,
                               height: request.display?.height ?? 1080)
            scale = screenScale(for: request.display)
        }

        let pixelSize = fittedPixelSize(CGSize(width: pointSize.width * scale,
                                               height: pointSize.height * scale))
        configuration.width = pixelSize.width
        configuration.height = pixelSize.height
        return configuration
    }

    private func screenScale(for display: SCDisplay?) -> CGFloat {
        guard let display else { return 2 }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        }?.backingScaleFactor ?? 2
    }

    private func fittedPixelSize(_ size: CGSize) -> (width: Int, height: Int) {
        let maxDimension: CGFloat = 4096
        let factor = min(1, maxDimension / max(size.width, size.height))
        let width = max(2, Int(size.width * factor) / 2 * 2)
        let height = max(2, Int(size.height * factor) / 2 * 2)
        return (width, height)
    }

    private func completeWithError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didComplete else { return }
            self.didComplete = true
            self.isRecording = false
            self.stream = nil
            self.recordingOutput = nil
            _ = self.cursorTracker?.stop()
            self.cursorTracker = nil
            self.errorCallback?(error)
            self.clearCallbacks()
        }
    }

    private func clearCallbacks() {
        startedCallback = nil
        finishedCallback = nil
        errorCallback = nil
        recordingRequest = nil
        rawOutputURL = nil
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

enum RecordingError: LocalizedError {
    case missingSource
    case unsupportedSystem

    var errorDescription: String? {
        switch self {
        case .missingSource: return "没有可用的录制来源。"
        case .unsupportedSystem: return "录屏需要 macOS 15 或更高版本。"
        }
    }
}
