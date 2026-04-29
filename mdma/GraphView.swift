import SwiftUI
import AppKit
import Combine

// MARK: - Graph Data

struct GraphNode: Identifiable {
    let id:   UUID
    let url:  URL
    let name: String
    var pos:  CGPoint
    var vel:  CGPoint = .zero
    var connections: Int = 0
    var radius: CGFloat { max(10, min(28, 7 + CGFloat(connections) * 2.8)) }
}

struct GraphEdge {
    let a: UUID
    let b: UUID
}

// MARK: - Graph Simulation

final class GraphSimulation: ObservableObject {

    @Published var nodes: [UUID: GraphNode] = [:]
    @Published var edges: [GraphEdge]       = []
    @Published var isRunning = false

    // Tuning constants
    private let repulsion:   CGFloat = 9_000
    private let spring:      CGFloat = 0.035
    private let restLength:  CGFloat = 160
    private let gravity:     CGFloat = 0.018
    private let damping:     CGFloat = 0.82
    private let maxVel:      CGFloat = 12

    private var center: CGPoint = .zero
    private var timer:  Timer?

    // MARK: Build

    func build(tree: [FileItem], backlinkIndex: [URL: [URL]], size: CGSize) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        let allURLs = flatURLs(tree)
        guard !allURLs.isEmpty else { return }

        var urlToID: [URL: UUID] = [:]
        var newNodes: [UUID: GraphNode] = [:]

        for url in allURLs {
            let id    = UUID()
            let angle = CGFloat.random(in: 0 ..< .pi * 2)
            let dist  = CGFloat.random(in: 40 ..< 220)
            let pos   = CGPoint(x: center.x + cos(angle) * dist,
                                y: center.y + sin(angle) * dist)
            newNodes[id] = GraphNode(id: id, url: url,
                                     name: url.deletingPathExtension().lastPathComponent,
                                     pos: pos)
            urlToID[url] = id
        }

        var newEdges: [GraphEdge] = []
        var seen = Set<String>()
        for (target, sources) in backlinkIndex {
            guard let toID = urlToID[target] else { continue }
            for src in sources {
                guard let fromID = urlToID[src], fromID != toID else { continue }
                let key = [fromID, toID].map(\.uuidString).sorted().joined()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                newEdges.append(GraphEdge(a: fromID, b: toID))
                newNodes[fromID]?.connections += 1
                newNodes[toID]?.connections   += 1
            }
        }

        nodes = newNodes
        edges = newEdges
        startSimulation()
    }

    // MARK: Simulation

    func startSimulation() {
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 50.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopSimulation() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    // Pin a node (zero its velocity), used during drag
    func pin(_ id: UUID, at pos: CGPoint) {
        nodes[id]?.pos = pos
        nodes[id]?.vel = .zero
    }

    private func tick() {
        var work = nodes
        let list = Array(work.values)

        var maxSpeed: CGFloat = 0

        for i in list.indices {
            var n = list[i]
            var fx: CGFloat = 0
            var fy: CGFloat = 0

            // Repulsion from every other node
            for j in list.indices where j != i {
                let o  = list[j]
                let dx = n.pos.x - o.pos.x
                let dy = n.pos.y - o.pos.y
                let d2 = max(1, dx * dx + dy * dy)
                let d  = sqrt(d2)
                let f  = repulsion / d2
                fx += f * dx / d
                fy += f * dy / d
            }

            // Spring along connected edges
            for edge in edges {
                let other: UUID?
                if   edge.a == n.id { other = edge.b }
                else if edge.b == n.id { other = edge.a }
                else { other = nil }
                if let oid = other, let o = work[oid] {
                    let dx = o.pos.x - n.pos.x
                    let dy = o.pos.y - n.pos.y
                    let d  = max(1, sqrt(dx * dx + dy * dy))
                    let stretch = d - restLength
                    fx += spring * stretch * dx / d
                    fy += spring * stretch * dy / d
                }
            }

            // Weak gravity toward canvas centre
            fx += gravity * (center.x - n.pos.x)
            fy += gravity * (center.y - n.pos.y)

            // Integrate
            n.vel.x = (n.vel.x + fx) * damping
            n.vel.y = (n.vel.y + fy) * damping
            n.vel.x = n.vel.x.clamped(to: -maxVel ... maxVel)
            n.vel.y = n.vel.y.clamped(to: -maxVel ... maxVel)
            n.pos.x += n.vel.x
            n.pos.y += n.vel.y

            maxSpeed = max(maxSpeed, abs(n.vel.x) + abs(n.vel.y))
            work[n.id] = n
        }

        nodes = work

        // Converge: slow to a stop after graph settles
        if maxSpeed < 0.08 { stopSimulation() }
    }

    private func flatURLs(_ items: [FileItem]) -> [URL] {
        items.flatMap { $0.isDirectory ? flatURLs($0.children ?? []) : [$0.url] }
    }
}

// MARK: - GraphCanvasView (NSView)

/// NSView that owns the simulation drawing + mouse interaction.
final class GraphCanvasView: NSView {

    var sim: GraphSimulation?
    var onOpen: ((URL) -> Void)?

    private var draggingID: UUID?
    private var renderDisplayLink: CADisplayLink?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Setup

    func startDisplayLink() {
        guard renderDisplayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        renderDisplayLink = link
    }

    func stopDisplayLink() {
        renderDisplayLink?.invalidate()
        renderDisplayLink = nil
    }

    @objc private func handleDisplayLink(_ sender: CADisplayLink) {
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let sim else { return }

        MarkdownParser.bg.setFill()
        bounds.fill()

        let ctx = NSGraphicsContext.current!.cgContext

        // ── Edges ──────────────────────────────────────────────────────────
        ctx.setLineWidth(1)
        MarkdownParser.muted.withAlphaComponent(0.18).setStroke()

        for edge in sim.edges {
            guard let a = sim.nodes[edge.a], let b = sim.nodes[edge.b] else { continue }
            ctx.beginPath()
            ctx.move(to: a.pos)
            ctx.addLine(to: b.pos)
            ctx.strokePath()
        }

        // ── Nodes ──────────────────────────────────────────────────────────
        for node in sim.nodes.values {
            let r    = node.radius
            let rect = CGRect(x: node.pos.x - r, y: node.pos.y - r,
                              width: r * 2,       height: r * 2)

            // Fill
            let fill = node.connections > 0
                ? MarkdownParser.accent.withAlphaComponent(0.85)
                : MarkdownParser.muted.withAlphaComponent(0.45)
            fill.setFill()
            ctx.fillEllipse(in: rect)

            // Ring for high-connectivity nodes
            if node.connections >= 3 {
                MarkdownParser.accent.withAlphaComponent(0.4).setStroke()
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: rect.insetBy(dx: -2, dy: -2))
            }

            // Label
            let label = node.name as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font:            NSFont.systemFont(ofSize: max(9, min(12, r * 0.72))),
                .foregroundColor: MarkdownParser.text.withAlphaComponent(0.85)
            ]
            let sz  = label.size(withAttributes: attrs)
            let lx  = node.pos.x - sz.width / 2
            let ly  = node.pos.y + r + 3
            label.draw(at: NSPoint(x: lx, y: ly), withAttributes: attrs)
        }
    }

    // MARK: Mouse

    private func nodeAt(_ point: CGPoint) -> UUID? {
        sim?.nodes.values.first(where: { n in
            let dx = n.pos.x - point.x
            let dy = n.pos.y - point.y
            return sqrt(dx * dx + dy * dy) <= n.radius + 4
        })?.id
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        draggingID = nodeAt(pt)
        sim?.stopSimulation()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = draggingID else { return }
        let pt = convert(event.locationInWindow, from: nil)
        sim?.pin(id, at: pt)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard draggingID == nil || event.clickCount == 0 else {
            // Single click with no drag = open note
            let pt = convert(event.locationInWindow, from: nil)
            if let id = nodeAt(pt), let url = sim?.nodes[id]?.url {
                onOpen?(url)
            }
            draggingID = nil
            return
        }
        if let id = draggingID {
            sim?.nodes[id]?.vel = .zero
        }
        draggingID = nil
        sim?.startSimulation()
    }
}

// MARK: - NSViewRepresentable wrapper

private struct GraphCanvas: NSViewRepresentable {

    @ObservedObject var sim: GraphSimulation
    var onOpen: (URL) -> Void

    func makeNSView(context: Context) -> GraphCanvasView {
        let v = GraphCanvasView()
        v.sim    = sim
        v.onOpen = onOpen
        v.startDisplayLink()
        return v
    }

    func updateNSView(_ v: GraphCanvasView, context: Context) {
        v.sim    = sim
        v.onOpen = onOpen
        v.needsDisplay = true
    }

    static func dismantleNSView(_ v: GraphCanvasView, coordinator: ()) {
        v.stopDisplayLink()
    }
}

// MARK: - GraphView (SwiftUI shell)

struct GraphView: View {

    @Binding var isShowing: Bool
    var onOpen: (URL) -> Void

    @EnvironmentObject var fs: FileSystemManager
    @StateObject private var sim = GraphSimulation()

    @State private var didBuild = false

    var body: some View {
        ZStack {
            // Dim backdrop
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { isShowing = false }

            VStack(spacing: 0) {
                // Title bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Note Graph")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(MarkdownParser.heading))
                        Text("\(sim.nodes.count) notes · \(sim.edges.count) links")
                            .font(.system(size: 11))
                            .foregroundColor(Color(MarkdownParser.muted))
                    }
                    Spacer()
                    if sim.isRunning {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                            Text("Simulating…")
                                .font(.system(size: 11))
                                .foregroundColor(Color(MarkdownParser.muted))
                        }
                    }
                    Button { isShowing = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundColor(Color(MarkdownParser.muted))
                            .frame(width: 28, height: 28)
                            .background(Color(MarkdownParser.codeBg))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color(MarkdownParser.sidebar))

                Divider().opacity(0.12)

                // Canvas
                GraphCanvas(sim: sim) { url in
                    onOpen(url)
                    isShowing = false
                }
                .background(Color(MarkdownParser.bg))

                // Footer hint
                HStack {
                    Text("Drag to rearrange · Click to open · Nodes sized by link count")
                        .font(.system(size: 10))
                        .foregroundColor(Color(MarkdownParser.muted))
                    Spacer()
                    Button {
                        sim.build(tree: fs.tree, backlinkIndex: fs.backlinkIndex,
                                  size: CGSize(width: 700, height: 480))
                    } label: {
                        Label("Re-layout", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(MarkdownParser.muted))
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Color(MarkdownParser.sidebar))
            }
            .frame(width: 760, height: 560)
            .background(Color(MarkdownParser.bg))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.35), radius: 28, y: 10)
        }
        .onAppear {
            guard !didBuild else { return }
            didBuild = true
            sim.build(tree: fs.tree, backlinkIndex: fs.backlinkIndex,
                      size: CGSize(width: 760, height: 480))
        }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
