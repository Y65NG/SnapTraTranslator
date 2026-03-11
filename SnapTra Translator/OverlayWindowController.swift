import AppKit
import SwiftUI

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Debug OCR Border View

struct DebugOCRBorderView: View {
    var wordBoxes: [CGRect]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .stroke(Color.red, lineWidth: 3)
                    .background(Color.clear)

                ForEach(Array(wordBoxes.enumerated()), id: \.offset) { _, box in
                    let converted = convertNormalizedBox(box, in: geometry.size)
                    Rectangle()
                        .stroke(Color.green, lineWidth: 1.5)
                        .frame(width: converted.width, height: converted.height)
                        .position(x: converted.midX, y: converted.midY)
                }
            }
        }
    }

    private func convertNormalizedBox(_ box: CGRect, in size: CGSize) -> CGRect {
        let x = box.origin.x * size.width
        let y = (1 - box.origin.y - box.height) * size.height
        let width = box.width * size.width
        let height = box.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Debug Overlay Window Controller

final class DebugOverlayWindowController: NSWindowController {
    private var hostingView: NSHostingView<DebugOCRBorderView>

    override init(window: NSWindow?) {
        hostingView = NSHostingView(rootView: DebugOCRBorderView(wordBoxes: []))
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
    }

    convenience init() {
        self.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(at rect: CGRect, wordBoxes: [CGRect] = []) {
        guard let window else { return }
        hostingView.rootView = DebugOCRBorderView(wordBoxes: wordBoxes)
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}

// MARK: - Paragraph Highlight View

private struct ParagraphHighlightView: View {
    private let accentColor = Color(red: 0.18, green: 0.88, blue: 0.42)
    private let lineWidth: CGFloat = 2.5
    /// Half-width of the gradient beam in points
    private let beamHalfWidth: CGFloat = 25

    @State private var appeared = false
    /// Beam center x position in the Canvas coordinate space (0 = left edge)
    @State private var beamCenterX: CGFloat = -25

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cornerLength = min(min(size.width, size.height) * 0.22, 22)

            ZStack {
                // Layer 1 — ambient fill
                Rectangle()
                    .fill(accentColor.opacity(0.04))

                // Layer 2 — scan beam drawn via Canvas so coordinates are unambiguous
                Canvas { ctx, canvasSize in
                    let centerX = beamCenterX
                    let left  = max(0, centerX - beamHalfWidth)
                    let right = min(canvasSize.width, centerX + beamHalfWidth)
                    guard right > left else { return }

                    let beamRect = CGRect(x: left, y: 0, width: right - left, height: canvasSize.height)

                    // Map gradient stops to the clipped rect
                    let fullLeft  = centerX - beamHalfWidth
                    let fullRight = centerX + beamHalfWidth
                    let fullWidth = fullRight - fullLeft

                    // Build a gradient that covers the visible slice of the beam inside beamRect
                    let gradient = Gradient(stops: [
                        .init(color: accentColor.opacity(0),    location: 0),
                        .init(color: accentColor.opacity(0.55), location: 0.42),
                        .init(color: accentColor.opacity(0.85), location: 0.5),
                        .init(color: accentColor.opacity(0.55), location: 0.58),
                        .init(color: accentColor.opacity(0),    location: 1),
                    ])
                    // Extend gradient start/end beyond beamRect so only the
                    // correct slice of the gradient is visible inside beamRect
                    let gradStart = CGPoint(x: fullLeft,  y: canvasSize.height / 2)
                    let gradEnd   = CGPoint(x: fullRight, y: canvasSize.height / 2)

                    ctx.fill(
                        Path(beamRect),
                        with: .linearGradient(
                            gradient,
                            startPoint: gradStart,
                            endPoint: gradEnd
                        )
                    )
                }

                // Layer 3 — corner brackets
                cornerBrackets(size: size, cornerLength: cornerLength)
                    .stroke(
                        accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    appeared = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    beamCenterX = -beamHalfWidth
                    withAnimation(
                        .easeInOut(duration: 1.4)
                        .repeatForever(autoreverses: true)
                    ) {
                        beamCenterX = size.width + beamHalfWidth
                    }
                }
            }
        }
    }

    private func cornerBrackets(size: CGSize, cornerLength: CGFloat) -> Path {
        Path { path in
            let rect = CGRect(origin: .zero, size: size)

            // bottom-left
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))

            // bottom-right
            path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))

            // top-left
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))

            // top-right
            path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
        }
    }
}

final class ParagraphHighlightWindowController: NSWindowController {
    private let hostingView: NSHostingView<ParagraphHighlightView>

    override init(window: NSWindow?) {
        hostingView = NSHostingView(rootView: ParagraphHighlightView())
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
    }

    convenience init() {
        self.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(at rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else {
            hide()
            return
        }

        guard let window else { return }
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}

// MARK: - Overlay Window Controller

final class OverlayWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>
    private var lastAnchor: CGPoint?
    private var manualOrigin: CGPoint?
    private var dragStartOrigin: CGPoint?
    private let frameTolerance: CGFloat = 0.5

    init(model: AppModel) {
        hostingView = NSHostingView(rootView: AnyView(OverlayView().environmentObject(model)))
        let panel = OverlayPanel(
            contentRect: CGRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
    }

    /// 设置窗口是否接受鼠标事件
    func setInteractive(_ interactive: Bool) {
        window?.ignoresMouseEvents = !interactive
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(at anchor: CGPoint, makeKey: Bool = false) {
        guard let window else { return }
        lastAnchor = anchor
        let targetFrame = measuredFrame(for: anchor)

        if !window.isVisible {
            window.setFrame(targetFrame, display: true)
            window.orderFrontRegardless()
            if makeKey {
                window.makeKey()
            }
        } else {
            applyFrameIfNeeded(targetFrame)
        }
    }

    func move(to anchor: CGPoint) {
        guard let window else { return }
        lastAnchor = anchor
        manualOrigin = nil
        dragStartOrigin = nil
        guard window.isVisible else { return }

        let screenFrame = visibleScreenFrame(for: anchor)
        let origin = anchoredOrigin(for: anchor, size: window.frame.size, in: screenFrame)
        let targetFrame = CGRect(origin: origin, size: window.frame.size)
        applyFrameIfNeeded(targetFrame)
    }

    /// 将面板对齐到句子矩形（正上方或正下方，取决于哪侧空间更大）
    func alignToSentenceRect(_ sentenceRect: CGRect, animated: Bool = true) {
        guard let window else { return }

        // 强制 SwiftUI 重新布局以获得最新宽高
        hostingView.layoutSubtreeIfNeeded()
        let contentSize = hostingView.fittingSize

        let panelWidth  = contentSize.width
        let panelHeight = contentSize.height

        // 取句子中心点所在屏幕
        let midPoint = CGPoint(x: sentenceRect.midX, y: sentenceRect.midY)
        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(midPoint, $0.frame, false)
        }) ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? .zero

        // AppKit Y 轴向上：minY 是物理下边，maxY 是物理上边
        let gap: CGFloat = 8
        let spaceBelow = sentenceRect.minY - screenFrame.minY
        let spaceAbove = screenFrame.maxY - sentenceRect.maxY

        let panelY: CGFloat
        if spaceBelow >= panelHeight + gap {
            // 句子正下方（面板顶边贴近句子底边）
            panelY = sentenceRect.minY - panelHeight - gap
        } else {
            // 句子正上方（面板底边贴近句子顶边）
            panelY = sentenceRect.maxY + gap
        }

        // 水平左对齐句子，clamp 到屏幕范围内
        let margin: CGFloat = 8
        var panelX = sentenceRect.minX
        panelX = max(screenFrame.minX + margin, panelX)
        panelX = min(screenFrame.maxX - panelWidth - margin, panelX)

        let targetFrame = CGRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        if animated {
            applyFrameAnimated(targetFrame)
        } else {
            applyFrameIfNeeded(targetFrame)
        }
    }

    func beginManualPositioning() {
        guard let window, window.isVisible else { return }
        dragStartOrigin = window.frame.origin
        manualOrigin = window.frame.origin
    }

    func moveBy(translation: CGSize) {
        guard let window, window.isVisible else { return }

        let baseOrigin = dragStartOrigin ?? manualOrigin ?? window.frame.origin
        let proposedOrigin = CGPoint(
            x: baseOrigin.x + translation.width,
            y: baseOrigin.y - translation.height
        )
        let screenPoint = CGPoint(
            x: proposedOrigin.x + window.frame.width / 2,
            y: proposedOrigin.y + window.frame.height / 2
        )
        let screenFrame = visibleScreenFrame(for: screenPoint)
        let clamped = clampedOrigin(proposedOrigin, size: window.frame.size, in: screenFrame)

        manualOrigin = clamped
        applyOriginIfNeeded(clamped)
    }

    func endManualPositioning() {
        dragStartOrigin = nil
    }

    func refreshLayoutIfNeeded(at anchor: CGPoint? = nil) {
        guard let window else { return }
        guard window.isVisible else {
            if let anchor {
                lastAnchor = anchor
            }
            return
        }

        let effectiveAnchor = anchor ?? lastAnchor ?? CGPoint(x: window.frame.midX, y: window.frame.maxY)
        lastAnchor = effectiveAnchor
        let targetFrame = measuredFrame(for: effectiveAnchor)
        applyFrameIfNeeded(targetFrame)
    }

    func hide() {
        lastAnchor = nil
        manualOrigin = nil
        dragStartOrigin = nil
        window?.orderOut(nil)
    }

    private func measuredFrame(for anchor: CGPoint) -> CGRect {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let origin: CGPoint

        if let manualOrigin {
            let screenPoint = CGPoint(
                x: manualOrigin.x + size.width / 2,
                y: manualOrigin.y + size.height / 2
            )
            let screenFrame = visibleScreenFrame(for: screenPoint)
            origin = clampedOrigin(manualOrigin, size: size, in: screenFrame)
            self.manualOrigin = origin
        } else {
            let screenFrame = visibleScreenFrame(for: anchor)
            origin = anchoredOrigin(for: anchor, size: size, in: screenFrame)
        }

        return CGRect(origin: origin, size: size)
    }

    private func visibleScreenFrame(for anchor: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private func applyFrameAnimated(_ targetFrame: CGRect) {
        guard let window else { return }
        guard frameNeedsUpdate(from: window.frame, to: targetFrame) else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    private func applyFrameIfNeeded(_ targetFrame: CGRect) {
        guard let window else { return }
        guard frameNeedsUpdate(from: window.frame, to: targetFrame) else { return }

        let widthDelta = abs(window.frame.size.width - targetFrame.size.width)
        let heightDelta = abs(window.frame.size.height - targetFrame.size.height)
        if widthDelta <= frameTolerance, heightDelta <= frameTolerance {
            applyOriginIfNeeded(targetFrame.origin)
            return
        }

        window.setFrame(targetFrame, display: true)
    }

    private func applyOriginIfNeeded(_ targetOrigin: CGPoint) {
        guard let window else { return }

        let xNeedsUpdate = abs(window.frame.origin.x - targetOrigin.x) > frameTolerance
        let yNeedsUpdate = abs(window.frame.origin.y - targetOrigin.y) > frameTolerance
        guard xNeedsUpdate || yNeedsUpdate else { return }

        window.setFrameOrigin(targetOrigin)
    }

    private func frameNeedsUpdate(from current: CGRect, to target: CGRect) -> Bool {
        abs(current.origin.x - target.origin.x) > frameTolerance
            || abs(current.origin.y - target.origin.y) > frameTolerance
            || abs(current.size.width - target.size.width) > frameTolerance
            || abs(current.size.height - target.size.height) > frameTolerance
    }

    private func anchoredOrigin(for anchor: CGPoint, size: CGSize, in screenFrame: CGRect) -> CGPoint {
        let offset = CGPoint(x: 12, y: -12)
        let proposedOrigin = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y - size.height)
        return clampedOrigin(proposedOrigin, size: size, in: screenFrame)
    }

    private func clampedOrigin(_ proposedOrigin: CGPoint, size: CGSize, in screenFrame: CGRect) -> CGPoint {
        var origin = proposedOrigin
        let shadowMargin: CGFloat = 50
        let minX = screenFrame.minX + shadowMargin
        let maxX = screenFrame.maxX - size.width - shadowMargin
        let minY = screenFrame.minY + shadowMargin
        let maxY = screenFrame.maxY - size.height - shadowMargin
        origin.x = min(max(origin.x, minX), maxX)
        origin.y = min(max(origin.y, minY), maxY)
        return origin
    }
}
