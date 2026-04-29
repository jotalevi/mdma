import AppKit
import SwiftUI

// MARK: - SwiftUI Wrapper

struct TabBarNSView: NSViewRepresentable {
    @Binding var tabs:        [URL]
    @Binding var activeTab:   URL?
    @Binding var unsavedTabs: Set<URL>
    var onSelect:  (URL) -> Void
    var onClose:   (URL) -> Void
    var onReorder: ([URL]) -> Void
    var onTearOff: (URL) -> Void

    func makeNSView(context: Context) -> TabBarHostView {
        let v = TabBarHostView()
        v.onSelect  = onSelect
        v.onClose   = onClose
        v.onReorder = onReorder
        v.onTearOff = onTearOff
        v.update(tabs: tabs, activeTab: activeTab)
        v.updateUnsaved(unsavedTabs)
        return v
    }

    func updateNSView(_ v: TabBarHostView, context: Context) {
        v.onSelect  = onSelect
        v.onClose   = onClose
        v.onReorder = onReorder
        v.onTearOff = onTearOff
        v.update(tabs: tabs, activeTab: activeTab)
        v.updateUnsaved(unsavedTabs)
    }
}

// MARK: - Ghost Panel (borderless floating window rendered outside app bounds)

private final class GhostPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        isOpaque            = false
        backgroundColor     = .clear
        hasShadow           = false   // we draw our own shadow via the view
        level               = .floating + 1
        ignoresMouseEvents  = true
        collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

private final class GhostView: NSView {
    var tabName: String = "" { didSet { needsDisplay = true } }
    var isActive: Bool  = false

    override var isFlipped: Bool { false }
    override var isOpaque:  Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let W = bounds.width
        let H = bounds.height
        let r: CGFloat = 8

        // Shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 12,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)

        // Background
        let path = CGPath(roundedRect: CGRect(x: 2, y: 2, width: W - 4, height: H - 4),
                          cornerWidth: r, cornerHeight: r, transform: nil)
        ctx.addPath(path)
        let bg = MarkdownParser.bg.blended(withFraction: 0.12, of: .white) ?? MarkdownParser.bg
        ctx.setFillColor(bg.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Active underline
        ctx.setFillColor(MarkdownParser.accent.cgColor)
        ctx.fill(CGRect(x: 2, y: H - 5.5, width: W - 4, height: 1.5))

        // Border
        ctx.setStrokeColor(MarkdownParser.accent.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(path)
        ctx.strokePath()

        // Label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: MarkdownParser.heading
        ]
        let str = NSAttributedString(string: tabName, attributes: labelAttrs)
        str.draw(at: CGPoint(x: 12, y: (H - 14) / 2))
    }
}

// MARK: - TabBarHostView

final class TabBarHostView: NSView {

    // MARK: Callbacks
    var onSelect:  ((URL) -> Void)?
    var onClose:   ((URL) -> Void)?
    var onReorder: (([URL]) -> Void)?
    var onTearOff: ((URL) -> Void)?

    // MARK: Data
    private var tabs:        [URL]     = []
    private var activeTab:   URL?
    private var tabOrder:    [URL]     = []
    private var unsavedTabs: Set<URL>  = []

    // MARK: Layout
    private let tabH:    CGFloat = 36
    private let minTabW: CGFloat = 80
    private let maxTabW: CGFloat = 200
    private var tabW:    CGFloat = 160

    // MARK: Layers
    private var tabLayers: [URL: CALayer] = [:]

    // MARK: Hover
    private var hoveredURL:   URL?
    private var trackingArea: NSTrackingArea?

    // MARK: Drag
    private var dragURL:         URL?
    private var dragStartMouseX: CGFloat = 0
    private var dragStartTabX:   CGFloat = 0
    private var isDragging:      Bool    = false
    private var isOutsideTabBar: Bool    = false
    private var reorderCooldown: Bool    = false

    // Ghost window (rendered outside app window)
    private var ghostPanel:  GhostPanel?
    private var ghostView:   GhostView?
    // Mouse offset within the ghost for natural drag feel
    private var ghostMouseOffsetX: CGFloat = 0
    private var ghostMouseOffsetY: CGFloat = 0

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer           = true
        layer?.masksToBounds = false
        updateTrackingAreas()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange),
            name: .themeDidChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleThemeChange() {
        refreshAppearances()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = MarkdownParser.sidebar.cgColor
        }
        refreshAppearances()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: tabH) }
    override var isFlipped:            Bool   { true }
    override var isOpaque:             Bool   { true }
    override var acceptsFirstResponder: Bool  { true }

    // MARK: - Public Update

    func update(tabs newTabs: [URL], activeTab newActive: URL?) {
        self.tabs      = newTabs
        self.activeTab = newActive

        let removed = tabOrder.filter { !newTabs.contains($0) }
        let added   = newTabs.filter  { !tabOrder.contains($0) }
        tabOrder    = tabOrder.filter  { newTabs.contains($0) } + added

        for url in removed {
            if let l = tabLayers.removeValue(forKey: url) {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.12)
                CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
                l.opacity = 0
                CATransaction.commit()
            }
        }

        for url in added {
            let l = buildTabLayer(url: url)
            layer?.addSublayer(l)
            tabLayers[url] = l
            l.opacity = 0
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.15)
            l.opacity = 1
            CATransaction.commit()
        }

        recalcTabWidth()
        positionTabs(animated: !removed.isEmpty || !added.isEmpty)
        refreshAppearances()
    }

    func updateUnsaved(_ unsaved: Set<URL>) {
        guard unsaved != unsavedTabs else { return }
        unsavedTabs = unsaved
        refreshAppearances()
    }

    // MARK: - Layer Factory

    private func buildTabLayer(url: URL) -> CALayer {
        let root = CALayer()
        root.masksToBounds = false

        func sub(_ name: String) -> CALayer {
            let l = CALayer(); l.name = name; root.addSublayer(l); return l
        }
        func textSub(_ name: String) -> CATextLayer {
            let l = CATextLayer(); l.name = name
            l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            l.actions = ["contents": NSNull(), "foregroundColor": NSNull()]
            root.addSublayer(l); return l
        }

        _ = sub("bg"); _ = sub("line"); _ = sub("divider")
        let label = textSub("label")
        let close = textSub("close")

        label.string = url.deletingPathExtension().lastPathComponent
        label.fontSize = 12; label.truncationMode = .end; label.alignmentMode = .left
        close.string = "×"; close.fontSize = 15
        close.alignmentMode = .center; close.opacity = 0

        return root
    }

    // MARK: - Layout

    private func recalcTabWidth() {
        guard !tabs.isEmpty else { tabW = maxTabW; return }
        tabW = max(minTabW, min(maxTabW, bounds.width / CGFloat(tabs.count)))
    }

    private func positionTabs(animated: Bool) {
        for (idx, url) in tabOrder.enumerated() {
            guard let root = tabLayers[url] else { continue }
            if url == dragURL && isDragging && !isOutsideTabBar { continue }

            let targetX    = CGFloat(idx) * tabW
            let targetFrame = CGRect(x: targetX, y: 0, width: tabW, height: tabH)

            if animated, abs((root.presentation()?.frame.origin.x ?? root.frame.origin.x) - targetX) > 0.5 {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.18)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
                root.frame = targetFrame
                CATransaction.commit()
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                root.frame = targetFrame
                CATransaction.commit()
            }
            layoutSublayers(root: root, url: url)
        }
    }

    private func layoutSublayers(root: CALayer, url: URL) {
        let W = tabW; let H = tabH
        let isActive = url == activeTab

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Frames and non-color properties first
        root.sublayerNamed("bg")?.frame     = CGRect(x: 0, y: 0, width: W, height: H)
        root.sublayerNamed("line")?.frame   = CGRect(x: 0, y: H - 1.5, width: W, height: 1.5)
        root.sublayerNamed("line")?.opacity = isActive ? 1 : 0
        root.sublayerNamed("divider")?.frame = CGRect(x: W - 1, y: 6, width: 1, height: H - 12)

        if let icon = root.sublayerNamed("icon") as? CATextLayer {
            icon.frame = CGRect(x: 10, y: (H - 12) / 2, width: 12, height: 12)
        }
        if let label = root.sublayerNamed("label") as? CATextLayer {
            label.frame = CGRect(x: 12, y: (H - 14) / 2 - 1, width: W - 36, height: 15)
            label.font  = NSFont.systemFont(ofSize: 12, weight: isActive ? .medium : .regular)
        }
        if let close = root.sublayerNamed("close") as? CATextLayer {
            close.frame = CGRect(x: W - 22, y: (H - 16) / 2, width: 16, height: 16)
        }

        // Resolve all colors within the view's effective appearance so that
        // light-mode themes get light colors, not the dark-mode fallback.
        let isUnsaved = unsavedTabs.contains(url)
        let isHovered = url == hoveredURL

        effectiveAppearance.performAsCurrentDrawingAppearance {
            root.sublayerNamed("bg")?.backgroundColor = isActive
                ? MarkdownParser.bg.cgColor : NSColor.clear.cgColor
            root.sublayerNamed("line")?.backgroundColor    = MarkdownParser.accent.cgColor
            root.sublayerNamed("divider")?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor

            if let icon = root.sublayerNamed("icon") as? CATextLayer {
                icon.foregroundColor = (isActive ? MarkdownParser.accent : MarkdownParser.muted).cgColor
            }
            if let label = root.sublayerNamed("label") as? CATextLayer {
                label.foregroundColor = (isActive ? MarkdownParser.heading : MarkdownParser.text).cgColor
            }
            if let close = root.sublayerNamed("close") as? CATextLayer {
                // Unsaved + not hovering → show filled dot in accent color; otherwise → ×
                close.string          = (isUnsaved && !isHovered) ? "●" : "×"
                close.foregroundColor = (isUnsaved && !isHovered)
                    ? MarkdownParser.accent.withAlphaComponent(0.75).cgColor
                    : MarkdownParser.muted.withAlphaComponent(0.8).cgColor
            }
        }

        CATransaction.commit()
    }

    private func refreshAppearances() {
        for url in tabs {
            guard let root = tabLayers[url] else { continue }
            layoutSublayers(root: root, url: url)
        }
    }

    // MARK: - Tracking / Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let pt  = convert(event.locationInWindow, from: nil)
        let url = urlAt(x: pt.x)
        if url != hoveredURL { hoveredURL = url; updateCloseVisibility() }
        updateCursor(pt: pt)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredURL = nil
        updateCloseVisibility()
        NSCursor.arrow.set()
    }

    private func updateCloseVisibility() {
        for url in tabs {
            let isUnsaved = unsavedTabs.contains(url)
            let isHovered = url == hoveredURL
            // Show indicator when: hovering, active tab, or file has unsaved changes
            let show = isHovered || url == activeTab || isUnsaved
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.1)
            if let close = tabLayers[url]?.sublayerNamed("close") as? CATextLayer {
                // Switch between dot and X without animation on string change
                CATransaction.setDisableActions(true)
                close.string = (isUnsaved && !isHovered) ? "●" : "×"
                effectiveAppearance.performAsCurrentDrawingAppearance {
                    close.foregroundColor = (isUnsaved && !isHovered)
                        ? MarkdownParser.accent.withAlphaComponent(0.75).cgColor
                        : MarkdownParser.muted.withAlphaComponent(0.8).cgColor
                }
                CATransaction.setDisableActions(false)
                close.opacity = show ? 1 : 0
            }
            CATransaction.commit()
        }
    }

    private func updateCursor(pt: CGPoint) {
        if let url = urlAt(x: pt.x), isCloseHit(url: url, pt: pt) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard let url = urlAt(x: pt.x) else {
            window?.performDrag(with: event)
            return
        }

        if isCloseHit(url: url, pt: pt) {
            animateClose(url: url); return
        }

        let idx         = tabOrder.firstIndex(of: url) ?? 0
        dragURL         = url
        dragStartMouseX = pt.x
        dragStartTabX   = CGFloat(idx) * tabW
        isDragging      = false
        isOutsideTabBar = false
        // Offset within the tab so ghost doesn't jump to corner
        ghostMouseOffsetX = pt.x - dragStartTabX
        ghostMouseOffsetY = pt.y

        onSelect?(url)
    }

    override func mouseDragged(with event: NSEvent) {
        if dragURL == nil {
            window?.performDrag(with: event)
            return
        }

        guard let url = dragURL else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let dx = pt.x - dragStartMouseX

        if !isDragging {
            guard abs(dx) > 4 else { return }
            isDragging = true
        }

        let outsideNow = !bounds.insetBy(dx: 0, dy: -8).contains(pt)

        if outsideNow != isOutsideTabBar {
            isOutsideTabBar = outsideNow
            if outsideNow {
                // Leaving: hide source tab, show ghost panel
                tabLayers[url]?.opacity = 0
                showGhostPanel(url: url, screenPt: NSEvent.mouseLocation)
            } else {
                // Returning: hide ghost panel, restore source
                hideGhostPanel()
                tabLayers[url]?.opacity = 1
            }
        }

        if isOutsideTabBar {
            // Move the ghost panel to follow the mouse
            moveGhostPanel(screenPt: NSEvent.mouseLocation)
        } else {
            // Internal reorder: move source layer directly
            let sourceX = max(0, min(CGFloat(tabOrder.count - 1) * tabW, dragStartTabX + dx))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tabLayers[url]?.frame.origin.x = sourceX
            CATransaction.commit()

            let center    = sourceX + tabW / 2
            let targetIdx = max(0, min(tabOrder.count - 1, Int(center / tabW)))
            if let srcIdx = tabOrder.firstIndex(of: url),
               srcIdx != targetIdx,
               !reorderCooldown {
                animateReorder(url: url, from: srcIdx, to: targetIdx)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let url = dragURL else { return }

        if isDragging {
            let screenPt = NSEvent.mouseLocation
            let inWindow = window?.frame.contains(screenPt) ?? false

            if isOutsideTabBar || !inWindow {
                // Tear off
                animateTearOff(url: url)
                return
            } else {
                // Snap back to slot
                hideGhostPanel()
                tabLayers[url]?.opacity = 1
                snapSourceToSlot(url: url)
            }
        }

        dragURL         = nil
        isDragging      = false
        isOutsideTabBar = false
    }

    // MARK: - Ghost Panel Management

    private func showGhostPanel(url: URL, screenPt: NSPoint) {
        let size   = NSSize(width: tabW, height: tabH)
        let panel  = GhostPanel(size: size)
        let view   = GhostView(frame: NSRect(origin: .zero, size: size))
        view.tabName  = url.deletingPathExtension().lastPathComponent
        view.isActive = url == activeTab

        panel.contentView = view
        ghostPanel  = panel
        ghostView   = view

        positionGhostPanel(screenPt: screenPt)
        panel.orderFront(nil)
    }

    private func moveGhostPanel(screenPt: NSPoint) {
        positionGhostPanel(screenPt: screenPt)
    }

    private func positionGhostPanel(screenPt: NSPoint) {
        guard let panel = ghostPanel else { return }
        // Center the ghost under the cursor with the same offset as mousedown
        let origin = NSPoint(
            x: screenPt.x - ghostMouseOffsetX,
            y: screenPt.y - (tabH - ghostMouseOffsetY)
        )
        panel.setFrameOrigin(origin)
    }

    private func hideGhostPanel() {
        ghostPanel?.orderOut(nil)
        ghostPanel = nil
        ghostView  = nil
    }

    private func animateTearOff(url: URL) {
        let panel = ghostPanel

        // Animate ghost panel: scale down + fade
        if let pv = panel?.contentView {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                pv.animator().alphaValue = 0
            }, completionHandler: {
                panel?.orderOut(nil)
                self.ghostPanel = nil
                self.ghostView  = nil
                self.onTearOff?(url)
            })
        } else {
            hideGhostPanel()
            onTearOff?(url)
        }

        tabLayers[url]?.opacity = 0
        dragURL         = nil
        isDragging      = false
        isOutsideTabBar = false
    }

    // MARK: - Snap to Slot

    private func snapSourceToSlot(url: URL) {
        guard let source = tabLayers[url] else { return }
        let finalIdx = tabOrder.firstIndex(of: url) ?? 0
        let finalX   = CGFloat(finalIdx) * tabW

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        source.frame = CGRect(x: finalX, y: 0, width: tabW, height: tabH)
        CATransaction.commit()

        dragURL         = nil
        isDragging      = false
        isOutsideTabBar = false
    }

    // MARK: - Reorder

    private func animateReorder(url: URL, from srcIdx: Int, to destIdx: Int) {
        reorderCooldown = true

        var newOrder = tabOrder
        newOrder.remove(at: srcIdx)
        newOrder.insert(url, at: destIdx)
        tabOrder = newOrder

        for (idx, tabURL) in tabOrder.enumerated() {
            guard tabURL != url, let tabLayer = tabLayers[tabURL] else { continue }
            let targetX  = CGFloat(idx) * tabW
            let currentX = tabLayer.presentation()?.frame.origin.x ?? tabLayer.frame.origin.x
            guard abs(currentX - targetX) > 0.5 else { continue }

            CATransaction.begin()
            CATransaction.setAnimationDuration(0.16)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            tabLayer.frame = CGRect(x: targetX, y: 0, width: tabW, height: tabH)
            CATransaction.commit()
        }

        let reordered = tabOrder
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.reorderCooldown = false
            guard let self else { return }
            var newTabs = self.tabs
            newTabs.sort {
                (reordered.firstIndex(of: $0) ?? 0) < (reordered.firstIndex(of: $1) ?? 0)
            }
            self.tabs = newTabs
            self.onReorder?(newTabs)
        }
    }

    // MARK: - Close

    private func animateClose(url: URL) {
        guard let l = tabLayers[url] else { onClose?(url); return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        CATransaction.setCompletionBlock { [weak self] in self?.onClose?(url) }
        l.opacity   = 0
        l.transform = CATransform3DMakeScale(0.85, 0.85, 1)
        CATransaction.commit()
    }

    // MARK: - Hit Testing

    private func urlAt(x: CGFloat) -> URL? {
        guard !tabOrder.isEmpty else { return nil }
        let i = Int(x / tabW)
        guard i >= 0, i < tabOrder.count else { return nil }
        return tabOrder[i]
    }

    private func isCloseHit(url: URL, pt: CGPoint) -> Bool {
        guard let idx = tabOrder.firstIndex(of: url) else { return false }
        let tabX      = CGFloat(idx) * tabW
        let closeRect = CGRect(x: tabX + tabW - 26, y: (tabH - 20) / 2, width: 22, height: 20)
        return closeRect.contains(pt)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = MarkdownParser.sidebar.cgColor
        }
        recalcTabWidth()
        positionTabs(animated: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        recalcTabWidth()
        positionTabs(animated: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        MarkdownParser.sidebar.setFill()
        bounds.fill()
    }
}

// MARK: - CALayer helper

private extension CALayer {
    func sublayerNamed(_ name: String) -> CALayer? {
        sublayers?.first { $0.name == name }
    }
}
