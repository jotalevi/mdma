import AppKit

// MARK: - CodeBlockInfo

struct CodeBlockInfo {
    let charRange:   NSRange
    let lineNumbers: [Int]
    let language:    String
    let codeLines:   [String]
}

// MARK: - CodeBlockOverlayView

final class CodeBlockOverlayView: NSView {

    var codeLines:    [String] = [] { didSet { refreshCanvas() } }
    var language:     String   = "" { didSet { refreshCanvas() } }
    var isFolded:     Bool     = false { didSet { needsDisplay = true; needsLayout = true } }
    var onTap:        (() -> Void)?
    var onFoldToggle: (() -> Void)?

    let lineH:    CGFloat = 22
    let hPad:     CGFloat = 16
    let vPad:     CGFloat = 12
    let radius:   CGFloat = 8
    let fontSize: CGFloat = 12.5

    private let foldButtonSize: CGFloat = 18
    var gutterW: CGFloat { codeLines.count >= 10 ? 44 : 36 }

    override var isFlipped: Bool { true }
    override var isOpaque:  Bool { false }

    private var scrollView: NSScrollView?
    private var canvasView: CodeCanvasView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        // Fold button hit test (top-right area of gutter)
        let foldRect = NSRect(x: 4, y: 4, width: foldButtonSize, height: foldButtonSize)
        if foldRect.contains(pt) {
            onFoldToggle?()
            return
        }
        if !isFolded { onTap?() }
    }

    // MARK: - Height

    var preferredHeight: CGFloat {
        isFolded ? 32 : vPad * 3 + CGFloat(max(codeLines.count, 1)) * lineH
    }

    // MARK: - Canvas management

    private func ensureScrollView() {
        guard scrollView == nil else { return }

        let sv = NSScrollView()
        sv.hasHorizontalScroller    = true
        sv.hasVerticalScroller      = false
        sv.autohidesScrollers       = true
        sv.drawsBackground          = false
        sv.scrollerStyle            = .overlay
        sv.horizontalScrollElasticity = .none

        let canvas = CodeCanvasView()
        canvas.overlay = self
        sv.documentView = canvas

        addSubview(sv)
        scrollView = sv
        canvasView = canvas
    }

    private func refreshCanvas() {
        ensureScrollView()
        guard let canvas = canvasView else { return }
        canvas.codeLines = codeLines
        canvas.language  = language
        canvas.lineH     = lineH
        canvas.hPad      = hPad
        canvas.vPad      = vPad
        canvas.fontSize  = fontSize
        canvas.needsDisplay = true
        needsDisplay = true
        needsLayout  = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius  = radius
        layer?.masksToBounds = true

        if isFolded {
            scrollView?.isHidden = true
        } else {
            scrollView?.isHidden = false
            let gW     = gutterW
            let svRect = NSRect(x: gW, y: 0, width: max(0, bounds.width - gW), height: bounds.height)
            scrollView?.frame = svRect
            let naturalW  = computeNaturalWidth()
            let canvasW   = max(naturalW, svRect.width)
            canvasView?.frame = NSRect(x: 0, y: 0, width: canvasW, height: bounds.height)
        }
    }

    private func computeNaturalWidth() -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        ]
        let maxW = codeLines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
        return maxW + hPad * 2 + 24
    }

    // MARK: - Drawing (bg, gutter, border — no code text)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let W  = bounds.width
        let H  = bounds.height
        let gW = gutterW

        ctx.saveGState()

        // Rounded background
        let outerPath = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: W, height: H),
            cornerWidth: radius, cornerHeight: radius, transform: nil
        )
        ctx.addPath(outerPath)
        ctx.setFillColor(MarkdownParser.codeBg.cgColor)
        ctx.fillPath()

        ctx.addPath(outerPath)
        ctx.clip()

        // Gutter background
        let gutterBg = MarkdownParser.codeBg.blended(
            withFraction: 0.15, of: MarkdownParser.muted
        ) ?? MarkdownParser.codeBg
        ctx.setFillColor(gutterBg.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: gW, height: H))

        // Gutter border line
        ctx.setStrokeColor(MarkdownParser.tableBorder.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: gW, y: 0))
        ctx.addLine(to: CGPoint(x: gW, y: H))
        ctx.strokePath()

        if isFolded {
            // Folded summary: "▸ language (N lines)" centred vertically
            let label = isFolded
                ? "▸ \(language.isEmpty ? "code" : language) · \(codeLines.count) lines  —  click to expand"
                : ""
            let summaryAttrs: [NSAttributedString.Key: Any] = [
                .font:            NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: MarkdownParser.muted
            ]
            let str = NSAttributedString(string: label, attributes: summaryAttrs)
            let y   = (H - str.size().height) / 2
            str.draw(at: CGPoint(x: gW + 12, y: y))
        } else {
            // Language badge
            if !language.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font:            NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: MarkdownParser.muted
                ]
                let str = NSAttributedString(string: language, attributes: attrs)
                str.draw(at: CGPoint(x: W - str.size().width - hPad, y: 8))
            }

            // Line numbers
            for (i, _) in codeLines.enumerated() {
                let y = vPad + CGFloat(i) * lineH
                let numAttrs: [NSAttributedString.Key: Any] = [
                    .font:            NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: MarkdownParser.muted.withAlphaComponent(0.5)
                ]
                let numStr = NSAttributedString(string: "\(i + 1)", attributes: numAttrs)
                numStr.draw(at: CGPoint(
                    x: gW - numStr.size().width - 8,
                    y: y + (lineH - numStr.size().height) / 2
                ))
            }
        }

        ctx.restoreGState()

        // Fold toggle button (▾ / ▸) drawn in gutter top-left
        let foldSymbol = isFolded ? "▸" : "▾"
        let foldAttrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 10),
            .foregroundColor: MarkdownParser.muted.withAlphaComponent(0.6)
        ]
        let foldStr = NSAttributedString(string: foldSymbol, attributes: foldAttrs)
        foldStr.draw(at: CGPoint(
            x: (gW - foldStr.size().width) / 2,
            y: (foldButtonSize - foldStr.size().height) / 2 + 4
        ))

        // Outer border (drawn on top, not clipped)
        ctx.saveGState()
        ctx.setStrokeColor(MarkdownParser.tableBorder.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1.0)
        ctx.addPath(outerPath)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - CodeCanvasView (scrollable code text)

final class CodeCanvasView: NSView {

    var codeLines: [String] = []
    var language:  String   = ""
    weak var overlay: CodeBlockOverlayView?

    var lineH:    CGFloat = 22
    var hPad:     CGFloat = 16
    var vPad:     CGFloat = 12
    var fontSize: CGFloat = 12.5
    var gutterW:  CGFloat = 36

    override var isFlipped: Bool { true }
    override var isOpaque:  Bool { false }

    override func mouseDown(with event: NSEvent) { overlay?.onTap?() }

    override func draw(_ dirtyRect: NSRect) {
        for (i, line) in codeLines.enumerated() {
            let y = vPad + CGFloat(i) * lineH
            let highlighted = highlight(line: line, language: language)
            highlighted.draw(at: CGPoint(
                x: hPad,
                y: y + (lineH - highlighted.size().height) / 2
            ))
        }
    }

    // MARK: - Syntax Highlighting

    private func highlight(line: String, language: String) -> NSAttributedString {
        let base = NSMutableAttributedString(string: line, attributes: [
            .font:            NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: MarkdownParser.text
        ])
        let ns  = line as NSString
        let len = ns.length
        guard len > 0 else { return base }

        func rx(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p) }

        var painted = [NSRange]()
        func isPainted(_ r: NSRange) -> Bool {
            painted.contains { NSIntersectionRange($0, r).length > 0 }
        }
        func paint(_ r: NSRange, color: NSColor, bold: Bool = false) {
            guard !isPainted(r), r.location != NSNotFound, r.length > 0,
                  r.location + r.length <= base.length else { return }
            base.addAttribute(.foregroundColor, value: color, range: r)
            if bold {
                base.addAttribute(.font,
                    value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold), range: r)
            }
            painted.append(r)
        }

        let lang = language.lowercased()

        // Comments
        rx(#"//.*$"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
            paint($0.range, color: MarkdownParser.muted)
        }
        rx(#"#.*$"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
            paint($0.range, color: MarkdownParser.muted)
        }
        rx(#"/\*.*?\*/"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
            paint($0.range, color: MarkdownParser.muted)
        }
        rx(#"<!--.*?-->"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
            paint($0.range, color: MarkdownParser.muted)
        }

        // Strings
        let strColor = NSColor(srgbRed: 0.48, green: 0.76, blue: 0.45, alpha: 1)
        rx(#""(?:[^"\\]|\\.)*""#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
            paint($0.range, color: strColor)
        }
        rx(#"'(?:[^'\\]|\\.)*'"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
            paint($0.range, color: strColor)
        }
        rx(#"`(?:[^`\\]|\\.)*`"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
            paint($0.range, color: strColor)
        }

        // Numbers
        let numColor = NSColor(srgbRed: 0.85, green: 0.60, blue: 0.30, alpha: 1)
        rx(#"\b\d+\.?\d*\b"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
            paint($0.range, color: numColor)
        }

        // Keywords
        let kwColor = NSColor(srgbRed: 0.78, green: 0.48, blue: 0.95, alpha: 1)
        let keywords: [String]
        switch lang {
        case "swift":
            keywords = ["func","var","let","if","else","guard","return","for","while","in",
                        "class","struct","enum","protocol","extension","import","true","false",
                        "nil","self","super","init","deinit","override","static","final",
                        "private","public","internal","fileprivate","open","throws","try",
                        "catch","do","switch","case","default","break","continue","where",
                        "as","is","typealias","lazy","weak","unowned","mutating","inout",
                        "async","await","actor","some","any","Type"]
        case "js","javascript","ts","typescript":
            keywords = ["function","var","let","const","if","else","return","for","while",
                        "class","import","export","from","default","new","this","typeof",
                        "instanceof","true","false","null","undefined","async","await",
                        "switch","case","break","continue","try","catch","finally","throw",
                        "of","in","extends","super","static","get","set","void"]
        case "python","py":
            keywords = ["def","class","if","elif","else","for","while","in","not","and",
                        "or","return","import","from","as","with","try","except","finally",
                        "raise","pass","break","continue","True","False","None","lambda",
                        "yield","async","await","del","global","nonlocal","assert","is"]
        case "rust","rs":
            keywords = ["fn","let","mut","if","else","match","for","while","loop","in",
                        "struct","enum","impl","trait","use","pub","mod","return","true",
                        "false","None","Some","Ok","Err","self","Self","super","crate",
                        "async","await","move","ref","type","where","const","static","unsafe"]
        case "go":
            keywords = ["func","var","const","type","if","else","for","range","switch",
                        "case","default","return","break","continue","goto","fallthrough",
                        "defer","go","chan","select","struct","interface","map","import",
                        "package","nil","true","false","make","new","len","cap","append"]
        case "html","xml","svg":
            keywords = []
        case "css","scss","sass":
            keywords = ["import","from","to","not","and","or","only","all","screen",
                        "print","var","calc","url","rgb","rgba","hsl","hsla","none",
                        "auto","inherit","initial","unset","important"]
        default:
            keywords = ["if","else","for","while","do","return","function","class",
                        "import","export","const","var","let","true","false","null",
                        "undefined","nil","none","new","this","self","super","in","of",
                        "switch","case","default","break","continue","try","catch","throw"]
        }

        for kw in keywords {
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: kw) + #"\b"#
            rx(pattern)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
                paint($0.range, color: kwColor, bold: true)
            }
        }

        // Types / capitalized identifiers
        let typeColor = NSColor(srgbRed: 0.40, green: 0.75, blue: 0.90, alpha: 1)
        rx(#"\b[A-Z][A-Za-z0-9_]+\b"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
            paint($0.range, color: typeColor)
        }

        // Function calls
        let fnColor = NSColor(srgbRed: 0.98, green: 0.82, blue: 0.45, alpha: 1)
        rx(#"\b([a-z_][a-zA-Z0-9_]*)\s*\("#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach { m in
            paint(m.range(at: 1), color: fnColor)
        }

        // Operators
        let opColor = MarkdownParser.muted.withAlphaComponent(0.75)
        rx(#"[=<>!&|+\-*/%^~]+"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
            paint($0.range, color: opColor)
        }

        // HTML/XML tags
        if lang == "html" || lang == "xml" || lang == "svg" {
            let tagColor  = NSColor(srgbRed: 0.78, green: 0.48, blue: 0.95, alpha: 1)
            let attrColor = NSColor(srgbRed: 0.40, green: 0.75, blue: 0.90, alpha: 1)
            rx(#"</?[a-zA-Z][a-zA-Z0-9-]*"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
                paint($0.range, color: tagColor)
            }
            rx(#"\b[a-z-]+=(?="|')"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
                paint($0.range, color: attrColor)
            }
            rx(#"[<>/]"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach {
                paint($0.range, color: opColor)
            }
        }

        return base
    }
}
