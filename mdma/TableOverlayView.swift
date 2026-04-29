import AppKit

// MARK: - TableInfo

struct TableInfo {
    let charRange:   NSRange
    let lineNumbers: [Int]
    let rows:        [[String]]
    let hasHeader:   Bool
    let colCount:    Int
}

// MARK: - TableOverlayView

final class TableOverlayView: NSView {

    var rows:       [[String]]  = []
    var rowHeights: [CGFloat]   = []   // one height per data row
    var hasHeader:  Bool        = false
    var colCount:   Int         = 0
    var onTap:      (() -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque:  Bool { false }

    override func mouseDown(with event: NSEvent) { onTap?() }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty, colCount > 0,
              let ctx = NSGraphicsContext.current?.cgContext else { return }

        let nCols   = colCount
        let W       = bounds.width
        let colW    = W / CGFloat(nCols)
        let totalH  = bounds.height
        let radius: CGFloat = 10

        // Compute y-offsets from row heights
        var yOffsets: [CGFloat] = []
        var y: CGFloat = 0
        for h in rowHeights {
            yOffsets.append(y)
            y += h
        }

        ctx.saveGState()

        // ── Clip to rounded rect ──────────────────────────────────────────
        let outerPath = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: W, height: totalH),
            cornerWidth: radius, cornerHeight: radius, transform: nil
        )
        ctx.addPath(outerPath)
        ctx.clip()

        // ── Cell backgrounds ──────────────────────────────────────────────
        for (ri, _) in rows.enumerated() {
            guard ri < rowHeights.count else { continue }
            let isHeader = hasHeader && ri == 0
            let bg: NSColor = isHeader     ? MarkdownParser.tableHead
                            : ri % 2 == 1 ? MarkdownParser.tableOdd
                                           : MarkdownParser.tableEven
            let rowRect = CGRect(x: 0, y: yOffsets[ri], width: W, height: rowHeights[ri])
            ctx.setFillColor(bg.cgColor)
            ctx.fill(rowRect)
        }

        // ── Cell text ─────────────────────────────────────────────────────
        for (ri, row) in rows.enumerated() {
            guard ri < rowHeights.count else { continue }
            let isHeader = hasHeader && ri == 0
            for ci in 0..<nCols {
                let cellRect = CGRect(
                    x:      CGFloat(ci) * colW,
                    y:      yOffsets[ri],
                    width:  colW,
                    height: rowHeights[ri]
                )
                let cellText = ci < row.count ? row[ci] : ""
                if !cellText.isEmpty {
                    drawCellText(cellText, in: cellRect, isHeader: isHeader)
                }
            }
        }

        // ── Inner grid lines ──────────────────────────────────────────────
        ctx.setStrokeColor(MarkdownParser.tableBorder.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(0.5)

        // Horizontal lines between rows
        for ri in 1..<rows.count {
            guard ri < yOffsets.count else { continue }
            let lineY = yOffsets[ri]
            ctx.move(to: CGPoint(x: 0, y: lineY))
            ctx.addLine(to: CGPoint(x: W, y: lineY))
        }
        // Vertical lines between cols
        for ci in 1..<nCols {
            let x = CGFloat(ci) * colW
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: totalH))
        }
        ctx.strokePath()

        // Header bottom separator — stronger
        if hasHeader && rows.count > 1, !rowHeights.isEmpty {
            ctx.setLineWidth(1.0)
            ctx.setStrokeColor(MarkdownParser.tableBorder.cgColor)
            let lineY = rowHeights[0]
            ctx.move(to: CGPoint(x: 0, y: lineY))
            ctx.addLine(to: CGPoint(x: W, y: lineY))
            ctx.strokePath()
        }

        ctx.restoreGState()

        // ── Outer border ──────────────────────────────────────────────────
        ctx.saveGState()
        ctx.setStrokeColor(MarkdownParser.tableBorder.cgColor)
        ctx.setLineWidth(1.0)
        ctx.addPath(outerPath)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Cell text

    private func drawCellText(_ raw: String, in rect: CGRect, isHeader: Bool) {
        let baseFont: NSFont = isHeader
            ? (NSFont(name: "Georgia-Bold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13))
            : (NSFont(name: "Georgia",      size: 13) ?? NSFont.systemFont(ofSize: 13))
        let baseColor = isHeader ? MarkdownParser.heading : MarkdownParser.text

        let styled = styledString(raw, font: baseFont, color: baseColor)
        let hPad: CGFloat = 14
        let maxW = rect.width - hPad * 2
        let sz = styled.boundingRect(
            with:    NSSize(width: maxW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textY = rect.minY + (rect.height - sz.height) / 2
        styled.draw(in: NSRect(x: rect.minX + hPad, y: textY, width: maxW, height: sz.height))
    }

    // MARK: - Inline styled string

    private func styledString(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: color])
        let ns  = text as NSString
        let len = ns.length

        func rx(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p) }
        func hide(_ r: NSRange) {
            guard r.location != NSNotFound, r.length > 0,
                  r.location + r.length <= result.length else { return }
            result.addAttributes([
                .font: NSFont.systemFont(ofSize: 0.001),
                .foregroundColor: NSColor.clear
            ], range: r)
        }

        rx(#"\*\*\*(.+?)\*\*\*"#)?.matches(in: text, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                let c = m.range(at: 1)
                hide(NSRange(location: m.range.location, length: 3))
                result.addAttribute(.font, value: NSFont(name: "Georgia-BoldItalic", size: 13) ?? font, range: c)
                hide(NSRange(location: c.location+c.length, length: 3))
            }
        rx(#"\*\*(.+?)\*\*"#)?.matches(in: text, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                let c = m.range(at: 1)
                hide(NSRange(location: m.range.location, length: 2))
                result.addAttribute(.font, value: NSFont(name: "Georgia-Bold", size: 13) ?? font, range: c)
                hide(NSRange(location: c.location+c.length, length: 2))
            }
        rx(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)?.matches(in: text, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                let c = m.range(at: 1)
                hide(NSRange(location: m.range.location, length: 1))
                result.addAttribute(.font, value: NSFont(name: "Georgia-Italic", size: 13) ?? font, range: c)
                hide(NSRange(location: c.location+c.length, length: 1))
            }
        rx(#"`(.+?)`"#)?.matches(in: text, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                let c = m.range(at: 1)
                hide(NSRange(location: m.range.location, length: 1))
                result.addAttributes([
                    .font:            NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: MarkdownParser.codeColor,
                    .backgroundColor: MarkdownParser.codeBg
                ], range: c)
                hide(NSRange(location: c.location+c.length, length: 1))
            }
        rx(#"~~(.+?)~~"#)?.matches(in: text, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                let c = m.range(at: 1)
                hide(NSRange(location: m.range.location, length: 2))
                result.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor:    MarkdownParser.muted
                ], range: c)
                hide(NSRange(location: c.location+c.length, length: 2))
            }
        rx(#"\$(\S[^$\n]*\S|\S)\$"#)?.matches(in: text, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                let c = m.range(at: 1)
                hide(NSRange(location: m.range.location, length: 1))
                result.addAttribute(.foregroundColor, value: MarkdownParser.accent, range: c)
                hide(NSRange(location: c.location+c.length, length: 1))
            }
        rx(#"@(\S[^@\n]*\S|\S)@"#)?.matches(in: text, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                let c = m.range(at: 1)
                hide(NSRange(location: m.range.location, length: 1))
                result.addAttribute(.foregroundColor, value: MarkdownParser.contactCol, range: c)
                hide(NSRange(location: c.location+c.length, length: 1))
            }
        rx(#"\|(\S[^|\n]*\S|\S)\|"#)?.matches(in: text, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                let c = m.range(at: 1)
                hide(NSRange(location: m.range.location, length: 1))
                result.addAttribute(.foregroundColor, value: MarkdownParser.fileRefCol, range: c)
                hide(NSRange(location: c.location+c.length, length: 1))
            }
        rx(#"\[(.+?)\]\((.+?)\)"#)?.matches(in: text, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                let textR = m.range(at: 1); let full = m.range
                hide(NSRange(location: full.location, length: 1))
                result.addAttribute(.foregroundColor, value: MarkdownParser.linkColor, range: textR)
                hide(NSRange(location: textR.location+textR.length,
                             length: full.location+full.length-textR.location-textR.length))
            }

        return result
    }
}
