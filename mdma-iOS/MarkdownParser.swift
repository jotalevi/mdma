import UIKit

struct MarkdownParser {

    // MARK: - Colors (from ThemeManager)
    static var bg:          UIColor { ThemeManager.shared.colors.bg          }
    static var sidebar:     UIColor { ThemeManager.shared.colors.sidebar     }
    static var text:        UIColor { ThemeManager.shared.colors.text        }
    static var heading:     UIColor { ThemeManager.shared.colors.heading     }
    static var accent:      UIColor { ThemeManager.shared.colors.accent      }
    static var muted:       UIColor { ThemeManager.shared.colors.muted       }
    static var quote:       UIColor { ThemeManager.shared.colors.quote       }
    static var codeColor:   UIColor { ThemeManager.shared.colors.codeColor   }
    static var codeBg:      UIColor { ThemeManager.shared.colors.codeBg      }
    static var linkColor:   UIColor { ThemeManager.shared.colors.linkColor   }
    static var syntaxCol:   UIColor { ThemeManager.shared.colors.syntaxCol   }
    static var tableHead:   UIColor { ThemeManager.shared.colors.tableHead   }
    static var tableEven:   UIColor { ThemeManager.shared.colors.tableEven   }
    static var tableOdd:    UIColor { ThemeManager.shared.colors.tableOdd    }
    static var tableBorder: UIColor { ThemeManager.shared.colors.tableBorder }
    static var greenCol:    UIColor { ThemeManager.shared.colors.greenCol    }
    static var contactCol:  UIColor { ThemeManager.shared.colors.contactCol  }
    static var fileRefCol:  UIColor { ThemeManager.shared.colors.fileRefCol  }

    // MARK: - Fonts
    static let bodyFont  = UIFont(name: "Georgia",      size: 16) ?? UIFont.systemFont(ofSize: 16)
    static let monoFont  = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static let monoSmall = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let tagFont   = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

    static let tableRowHeight: CGFloat = 36
    static let codeLineHeight: CGFloat = 22

    static func defaultAttrs() -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 5; ps.paragraphSpacing = 2
        return [.font: bodyFont, .foregroundColor: text, .paragraphStyle: ps]
    }

    // MARK: - Main Entry

    static func applyStyle(to ts: NSTextStorage, activeLine: Int) {
        ts.setAttributes(defaultAttrs(), range: NSRange(location: 0, length: ts.length))

        let lines = ts.string.components(separatedBy: "\n")
        var offset        = 0
        var inCode        = false
        var codeStart     = 0
        var codeFenceLine = 0
        var codeBodyLines: [String] = []
        var codeLineNums:  [Int]    = []

        var i = 0
        while i < lines.count {
            let line      = lines[i]
            let lineLen   = (line as NSString).length
            let lineRange = NSRange(location: offset, length: lineLen)

            // ── Fenced code block ──────────────────────────────────────────
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if !inCode {
                    inCode        = true
                    codeStart     = offset
                    codeFenceLine = i
                    codeBodyLines = []
                    codeLineNums  = [i]
                    ts.addAttributes([
                        .font:            monoSmall,
                        .foregroundColor: syntaxCol,
                        .backgroundColor: codeBg
                    ], range: lineRange)
                } else {
                    codeLineNums.append(i)
                    let isActive = codeLineNums.contains(activeLine)
                    // Opening fence offset
                    var openOffset = 0
                    for (li, l) in lines.enumerated() {
                        if li == codeFenceLine { break }
                        openOffset += (l as NSString).length + 1
                    }
                    let openLen = (lines[codeFenceLine] as NSString).length

                    if isActive {
                        ts.addAttributes([.font: monoSmall, .foregroundColor: syntaxCol,
                                          .backgroundColor: codeBg],
                                         range: NSRange(location: openOffset, length: openLen))
                        var bodyOffset = openOffset + openLen + 1
                        for bodyLine in codeBodyLines {
                            let blen = (bodyLine as NSString).length
                            ts.addAttributes([.font: monoSmall, .foregroundColor: codeColor,
                                              .backgroundColor: codeBg],
                                             range: NSRange(location: bodyOffset, length: blen))
                            bodyOffset += blen + 1
                        }
                        ts.addAttributes([.font: monoSmall, .foregroundColor: syntaxCol,
                                          .backgroundColor: codeBg], range: lineRange)
                    } else {
                        // Collapse fences, show body with codeBg
                        styleCollapsed(ts, range: NSRange(location: openOffset, length: openLen))
                        styleCollapsed(ts, range: lineRange)
                        var bodyOffset = openOffset + openLen + 1
                        let count = codeBodyLines.count
                        for (bi, bodyLine) in codeBodyLines.enumerated() {
                            let blen = (bodyLine as NSString).length
                            var h    = codeLineHeight
                            if count == 1 {
                                h = codeLineHeight * 3 + 2
                            } else {
                                if bi == 0         { h += codeLineHeight }
                                if bi == count - 1 { h += codeLineHeight + 2 }
                            }
                            ts.addAttributes([
                                .font:            monoSmall,
                                .foregroundColor: codeColor,
                                .backgroundColor: codeBg,
                                .paragraphStyle:  fixedLinePS(h)
                            ], range: NSRange(location: bodyOffset, length: blen))
                            bodyOffset += blen + 1
                        }
                    }
                    inCode = false
                }
                offset += lineLen + 1; i += 1; continue
            }

            if inCode {
                codeLineNums.append(i)
                codeBodyLines.append(line)
                offset += lineLen + 1; i += 1; continue
            }

            // ── Normal line ───────────────────────────────────────────────
            if !line.isEmpty {
                if i == activeLine { styleActive(line: line, range: lineRange, in: ts) }
                else               { styleRendered(line: line, range: lineRange, in: ts) }
            }
            offset += lineLen + 1; i += 1
        }
    }

    // MARK: - Paragraph Style Helpers

    private static func fixedLinePS(_ h: CGFloat) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight      = h
        ps.maximumLineHeight      = h
        ps.lineSpacing            = 0
        ps.paragraphSpacing       = 0
        ps.paragraphSpacingBefore = 0
        return ps
    }

    private static func styleCollapsed(_ ts: NSTextStorage, range: NSRange) {
        guard range.location != NSNotFound, range.length > 0,
              range.location + range.length <= ts.length else { return }
        let ps = NSMutableParagraphStyle()
        ps.minimumLineHeight      = 0.001
        ps.maximumLineHeight      = 0.001
        ps.lineSpacing            = 0
        ps.paragraphSpacing       = 0
        ps.paragraphSpacingBefore = 0
        ps.lineHeightMultiple     = 0.001
        ts.addAttributes([
            .font:            UIFont.systemFont(ofSize: 0.001),
            .foregroundColor: bg,
            .backgroundColor: bg,
            .paragraphStyle:  ps,
            .baselineOffset:  -999
        ], range: range)
    }

    // MARK: - Active Line

    private static func styleActive(line: String, range: NSRange, in ts: NSTextStorage) {
        let ns  = line as NSString
        let len = ns.length
        let loc = range.location
        for p in ["### ", "## ", "# ", "> ", "- [ ] ", "- [x] ", "- [X] ", "- ", "* "] where line.hasPrefix(p) {
            ts.addAttribute(.foregroundColor, value: syntaxCol,
                            range: NSRange(location: loc, length: (p as NSString).length))
            break
        }
        rx(#"\$(\S[^$\n]*\S|\S)\$"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach { m in
            ts.addAttribute(.foregroundColor, value: accent,
                            range: NSRange(location: loc + m.range.location, length: m.range.length))
        }
        rx(#"@(\S[^@\n]*\S|\S)@"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach { m in
            ts.addAttribute(.foregroundColor, value: contactCol,
                            range: NSRange(location: loc + m.range.location, length: m.range.length))
        }
        rx(#"\|(\S[^|\n]*\S|\S)\|"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach { m in
            ts.addAttribute(.foregroundColor, value: fileRefCol,
                            range: NSRange(location: loc + m.range.location, length: m.range.length))
        }
        rx(#"(?:https?://|www\.)[^\s\)]+"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach { m in
            ts.addAttribute(.foregroundColor, value: linkColor,
                            range: NSRange(location: loc + m.range.location, length: m.range.length))
        }
    }

    // MARK: - Rendered Line

    private static func styleRendered(line: String, range: NSRange, in ts: NSTextStorage) {
        let loc = range.location
        if line.hasPrefix("# "), line.count > 2 {
            let pl = 2; hide(ts, NSRange(location: loc, length: pl))
            ts.addAttributes([.font: UIFont.boldSystemFont(ofSize: 30),
                              .foregroundColor: heading, .paragraphStyle: hStyle(14, 6)],
                             range: NSRange(location: loc+pl, length: range.length-pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line.hasPrefix("## "), line.count > 3 {
            let pl = 3; hide(ts, NSRange(location: loc, length: pl))
            ts.addAttributes([.font: UIFont.boldSystemFont(ofSize: 22),
                              .foregroundColor: heading, .paragraphStyle: hStyle(10, 4)],
                             range: NSRange(location: loc+pl, length: range.length-pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line.hasPrefix("### "), line.count > 4 {
            let pl = 4; hide(ts, NSRange(location: loc, length: pl))
            ts.addAttributes([.font: UIFont.boldSystemFont(ofSize: 17),
                              .foregroundColor: heading, .paragraphStyle: hStyle(8, 2)],
                             range: NSRange(location: loc+pl, length: range.length-pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line.hasPrefix("#### "), line.count > 5 {
            let pl = 5; hide(ts, NSRange(location: loc, length: pl))
            ts.addAttributes([.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: heading],
                             range: NSRange(location: loc+pl, length: range.length-pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line.hasPrefix("> ") {
            let pl = 2; hide(ts, NSRange(location: loc, length: pl))
            let ps = NSMutableParagraphStyle()
            ps.headIndent = 18; ps.firstLineHeadIndent = 18; ps.lineSpacing = 4
            ts.addAttributes([.font: UIFont(name: "Georgia-Italic", size: 16) ?? bodyFont,
                              .foregroundColor: quote, .paragraphStyle: ps],
                             range: NSRange(location: loc+pl, length: range.length-pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line == "---" || line == "***" || line == "___" {
            ts.addAttributes([.foregroundColor: bg, .font: bodyFont], range: range); return
        }
        if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
            let pl = 6; hide(ts, NSRange(location: loc, length: pl))
            ts.addAttributes([.foregroundColor: muted,
                              .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                              .strikethroughColor: contactCol],
                             range: NSRange(location: loc+pl, length: range.length-pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line.hasPrefix("- [ ] ") {
            let pl = 6; hide(ts, NSRange(location: loc, length: pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if (line.hasPrefix("- ") || line.hasPrefix("* ")), line.count > 2 {
            let pl = 2
            ts.addAttribute(.foregroundColor, value: accent, range: NSRange(location: loc, length: 1))
            hide(ts, NSRange(location: loc+1, length: 1))
            let ps = NSMutableParagraphStyle()
            ps.headIndent = 18; ps.firstLineHeadIndent = 4; ps.lineSpacing = 4
            ts.addAttribute(.paragraphStyle, value: ps, range: range)
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line.hasPrefix("  - ") || line.hasPrefix("    - ") {
            let indent: Int    = line.hasPrefix("    - ") ? 6 : 4
            let depth: CGFloat = line.hasPrefix("    ") ? 36 : 24
            hide(ts, NSRange(location: loc, length: indent))
            let ps = NSMutableParagraphStyle()
            ps.headIndent = depth+12; ps.firstLineHeadIndent = depth; ps.lineSpacing = 4
            ts.addAttribute(.paragraphStyle, value: ps, range: range)
            applyInlineStyles(ts, line: String(line.dropFirst(indent)), lineStart: loc+indent); return
        }
        if let m = rx(#"^(\d+\.\s)"#)?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            let pl = m.range.length
            ts.addAttribute(.foregroundColor, value: accent, range: NSRange(location: loc, length: pl))
            let ps = NSMutableParagraphStyle()
            ps.headIndent = 22; ps.firstLineHeadIndent = 4; ps.lineSpacing = 4
            ts.addAttribute(.paragraphStyle, value: ps, range: range)
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        applyInlineStyles(ts, line: line, lineStart: loc)
    }

    // MARK: - Inline Styles

    static func applyInlineStyles(_ ts: NSTextStorage, line: String, lineStart: Int, tagsOnly: Bool = false) {
        let ns  = line as NSString
        let len = ns.length

        var codeRanges: [NSRange] = []
        rx(#"`(.+?)`"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach { m in
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart + m.range.location, length: 1))
            ts.addAttributes([.font: monoFont, .foregroundColor: codeColor, .backgroundColor: codeBg],
                             range: NSRange(location: lineStart + c.location, length: c.length))
            hide(ts, NSRange(location: lineStart + c.location + c.length, length: 1))
            codeRanges.append(m.range)
        }
        func inCode(_ r: NSRange) -> Bool {
            codeRanges.contains { NSIntersectionRange($0, r).length > 0 }
        }

        // $tag$
        rx(#"\$(\S[^$\n]*\S|\S)\$"#)?.matches(in: line, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                guard !inCode(m.range) else { return }
                let absRange = NSRange(location: lineStart + m.range.location, length: m.range.length)
                guard absRange.location + absRange.length <= ts.length else { return }
                let inner   = m.range(at: 1)
                let tagName = ns.substring(with: inner).trimmingCharacters(in: .whitespaces)
                let slug    = tagName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tagName
                hide(ts, NSRange(location: lineStart + m.range.location, length: 1))
                ts.addAttributes([.foregroundColor: accent,
                                  .link: URL(string: "mdma://tag/\(slug)")!],
                                 range: NSRange(location: lineStart + inner.location, length: inner.length))
                hide(ts, NSRange(location: lineStart + inner.location + inner.length, length: 1))
            }
        // @person@
        rx(#"@(\S[^@\n]*\S|\S)@"#)?.matches(in: line, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                guard !inCode(m.range) else { return }
                let absRange = NSRange(location: lineStart + m.range.location, length: m.range.length)
                guard absRange.location + absRange.length <= ts.length else { return }
                let inner = m.range(at: 1)
                let name  = ns.substring(with: inner).trimmingCharacters(in: .whitespaces)
                let slug  = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                hide(ts, NSRange(location: lineStart + m.range.location, length: 1))
                ts.addAttributes([.foregroundColor: contactCol,
                                  .link: URL(string: "mdma://contact/\(slug)")!],
                                 range: NSRange(location: lineStart + inner.location, length: inner.length))
                hide(ts, NSRange(location: lineStart + inner.location + inner.length, length: 1))
            }
        // |file|
        rx(#"\|(\S[^|\n]*\S|\S)\|"#)?.matches(in: line, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                guard !inCode(m.range) else { return }
                let absRange = NSRange(location: lineStart + m.range.location, length: m.range.length)
                guard absRange.location + absRange.length <= ts.length else { return }
                let inner    = m.range(at: 1)
                let fileName = ns.substring(with: inner)
                let slug     = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
                hide(ts, NSRange(location: lineStart + m.range.location, length: 1))
                ts.addAttributes([.foregroundColor: fileRefCol,
                                  .link: URL(string: "mdma://ref/\(slug)")!],
                                 range: NSRange(location: lineStart + inner.location, length: inner.length))
                hide(ts, NSRange(location: lineStart + inner.location + inner.length, length: 1))
            }

        if tagsOnly { return }

        // Bold-italic ***
        rx(#"\*\*\*(.+?)\*\*\*"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 3))
            ts.addAttribute(.font, value: UIFont(name: "Georgia-BoldItalic", size: 16) ?? UIFont.boldSystemFont(ofSize: 16),
                            range: NSRange(location: lineStart+c.location, length: c.length))
            hide(ts, NSRange(location: lineStart+c.location+c.length, length: 3))
        }
        // Bold **
        rx(#"\*\*(.+?)\*\*"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 2))
            ts.addAttribute(.font, value: UIFont(name: "Georgia-Bold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16),
                            range: NSRange(location: lineStart+c.location, length: c.length))
            hide(ts, NSRange(location: lineStart+c.location+c.length, length: 2))
        }
        // Bold __
        rx(#"__(.+?)__"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 2))
            ts.addAttribute(.font, value: UIFont(name: "Georgia-Bold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16),
                            range: NSRange(location: lineStart+c.location, length: c.length))
            hide(ts, NSRange(location: lineStart+c.location+c.length, length: 2))
        }
        // Italic *
        rx(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 1))
            ts.addAttribute(.font, value: UIFont(name: "Georgia-Italic", size: 16) ?? bodyFont,
                            range: NSRange(location: lineStart+c.location, length: c.length))
            hide(ts, NSRange(location: lineStart+c.location+c.length, length: 1))
        }
        // Italic _
        rx(#"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 1))
            ts.addAttribute(.font, value: UIFont(name: "Georgia-Italic", size: 16) ?? bodyFont,
                            range: NSRange(location: lineStart+c.location, length: c.length))
            hide(ts, NSRange(location: lineStart+c.location+c.length, length: 1))
        }
        // Strikethrough
        rx(#"~~(.+?)~~"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 2))
            ts.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: muted],
                             range: NSRange(location: lineStart+c.location, length: c.length))
            hide(ts, NSRange(location: lineStart+c.location+c.length, length: 2))
        }
        // Links [text](url)
        rx(#"\[(.+?)\]\((https?://[^\)]+)\)"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let textR = m.range(at: 1); let urlR = m.range(at: 2)
            let urlStr = ns.substring(with: urlR)
            guard let url = URL(string: urlStr) else { return }
            hide(ts, NSRange(location: lineStart+m.range.location, length: 1))
            ts.addAttributes([.foregroundColor: linkColor, .link: url],
                             range: NSRange(location: lineStart+textR.location, length: textR.length))
            hide(ts, NSRange(location: lineStart+textR.location+textR.length,
                             length: m.range.location + m.range.length - textR.location - textR.length))
        }
        // Bare URLs
        rx(#"(?:https?://|www\.)[^\s\)]+"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach { m in
            guard !inCode(m.range) else { return }
            let urlStr = ns.substring(with: m.range)
            let full   = urlStr.hasPrefix("www.") ? "https://\(urlStr)" : urlStr
            if let url = URL(string: full) {
                ts.addAttributes([.foregroundColor: linkColor, .link: url],
                                 range: NSRange(location: lineStart + m.range.location, length: m.range.length))
            }
        }
    }

    // MARK: - Helpers

    static func hide(_ ts: NSTextStorage, _ r: NSRange) {
        guard r.location != NSNotFound, r.length > 0,
              r.location + r.length <= ts.length else { return }
        ts.addAttributes([
            .foregroundColor: UIColor.clear,
            .font: UIFont.systemFont(ofSize: 0.001)
        ], range: r)
    }

    static func hStyle(_ before: CGFloat, _ after: CGFloat) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacingBefore = before
        ps.paragraphSpacing       = after
        ps.lineSpacing            = 3
        return ps
    }

    static func rx(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [])
    }
}
