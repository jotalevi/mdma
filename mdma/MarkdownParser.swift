import AppKit

struct MarkdownParser {

    // MARK: - Colors (theme-aware — read from ThemeManager at call time)
    static var bg:          NSColor { ThemeManager.shared.colors.bg          }
    static var sidebar:     NSColor { ThemeManager.shared.colors.sidebar     }
    static var text:        NSColor { ThemeManager.shared.colors.text        }
    static var heading:     NSColor { ThemeManager.shared.colors.heading     }
    static var accent:      NSColor { ThemeManager.shared.colors.accent      }
    static var muted:       NSColor { ThemeManager.shared.colors.muted       }
    static var quote:       NSColor { ThemeManager.shared.colors.quote       }
    static var codeColor:   NSColor { ThemeManager.shared.colors.codeColor   }
    static var codeBg:      NSColor { ThemeManager.shared.colors.codeBg      }
    static var linkColor:   NSColor { ThemeManager.shared.colors.linkColor   }
    static var syntaxCol:   NSColor { ThemeManager.shared.colors.syntaxCol   }
    static var tableHead:   NSColor { ThemeManager.shared.colors.tableHead   }
    static var tableEven:   NSColor { ThemeManager.shared.colors.tableEven   }
    static var tableOdd:    NSColor { ThemeManager.shared.colors.tableOdd    }
    static var tableBorder: NSColor { ThemeManager.shared.colors.tableBorder }
    static var greenCol:    NSColor { ThemeManager.shared.colors.greenCol    }
    static var contactCol:  NSColor { ThemeManager.shared.colors.contactCol  }
    static var fileRefCol:  NSColor { ThemeManager.shared.colors.fileRefCol  }

    // Aliases
    static var backgroundColor: NSColor { bg          }
    static var sidebarColor:    NSColor { sidebar     }
    static var textColor:       NSColor { text        }
    static var headingColor:    NSColor { heading     }
    static var accentColor:     NSColor { accent      }
    static var mutedColor:      NSColor { muted       }
    static var tableBg:         NSColor { tableEven   }

    static let tableRowHeight: CGFloat = 36
    static let codeLineHeight: CGFloat = 22

    // MARK: - Fonts (dynamic — read from UserDefaults at call time)

    static var fontSize: CGFloat {
        let v = UserDefaults.standard.double(forKey: "fontSize")
        return CGFloat(v > 0 ? v : 15)
    }
    static var lineHeightMultiplier: CGFloat {
        let v = UserDefaults.standard.double(forKey: "lineHeightMultiplier")
        return CGFloat(v > 0 ? v : 1.3)
    }

    static var bodyFont: NSFont {
        let name = UserDefaults.standard.string(forKey: "bodyFontName") ?? "Georgia"
        return NSFont(name: name, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    }
    static var monoFont: NSFont {
        let name = UserDefaults.standard.string(forKey: "monoFontName")
        if let n = name, let f = NSFont(name: n, size: fontSize - 2) { return f }
        return NSFont.monospacedSystemFont(ofSize: fontSize - 2, weight: .regular)
    }
    static var monoSmall: NSFont {
        let name = UserDefaults.standard.string(forKey: "monoFontName")
        if let n = name, let f = NSFont(name: n, size: fontSize - 3) { return f }
        return NSFont.monospacedSystemFont(ofSize: fontSize - 3, weight: .regular)
    }
    static var tagFont: NSFont {
        let name = UserDefaults.standard.string(forKey: "monoFontName")
        if let n = name, let f = NSFont(name: n, size: fontSize - 4) { return f }
        return NSFont.monospacedSystemFont(ofSize: fontSize - 4, weight: .semibold)
    }

    // Font variants derived from the current body font family
    static var boldFont: NSFont {
        NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
    }
    static var italicFont: NSFont {
        NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
    }
    static var boldItalicFont: NSFont {
        let b = NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
        return NSFontManager.shared.convert(b, toHaveTrait: .italicFontMask)
    }

    static var ligaturesEnabled: Bool {
        UserDefaults.standard.bool(forKey: "ligatures")
    }

    static func defaultAttrs() -> [NSAttributedString.Key: Any] {
        let ps = NSMutableParagraphStyle()
        ps.lineHeightMultiple = lineHeightMultiplier
        ps.paragraphSpacing   = 2
        return [
            .font:             bodyFont,
            .foregroundColor:  text,
            .paragraphStyle:   ps,
            .ligature:         ligaturesEnabled ? 1 : 0
        ]
    }

    // MARK: - Main Entry

    @discardableResult
    static func applyStyle(to ts: NSTextStorage, activeLine: Int) -> (tables: [TableInfo], codeBlocks: [CodeBlockInfo]) {
        ts.setAttributes(defaultAttrs(), range: NSRange(location: 0, length: ts.length))

        let lines         = ts.string.components(separatedBy: "\n")
        var offset        = 0
        var inCode        = false
        var codeStart     = 0
        var codeFenceLine = 0
        var codeLang      = ""
        var codeLineNums:  [Int]    = []
        var codeBodyLines: [String] = []

        var tableInfos:     [TableInfo]     = []
        var codeBlockInfos: [CodeBlockInfo] = []

        var i = 0
        while i < lines.count {
            let line      = lines[i]
            let lineLen   = (line as NSString).length
            let lineRange = NSRange(location: offset, length: lineLen)

            // ── Fenced code block ─────────────────────────────────────────
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if !inCode {
                    // Opening fence — style tentatively
                    inCode        = true
                    codeStart     = offset
                    codeFenceLine = i
                    codeLang      = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLineNums  = [i]
                    codeBodyLines = []
                    ts.addAttributes([
                        .font:            monoSmall,
                        .foregroundColor: syntaxCol,
                        .backgroundColor: codeBg
                    ], range: lineRange)

                } else {
                    // Closing fence
                    codeLineNums.append(i)

                    let blockRange = NSRange(location: codeStart, length: offset + lineLen - codeStart)
                    let isActive   = codeLineNums.contains(activeLine)

                    // Opening fence offset
                    var openOffset = 0
                    for (li, l) in lines.enumerated() {
                        if li == codeFenceLine { break }
                        openOffset += (l as NSString).length + 1
                    }
                    let openLen = (lines[codeFenceLine] as NSString).length

                    if isActive {
                        // ── Edit mode: show both fences + body at fixed height ──
                        ts.addAttributes([
                            .font:            monoSmall,
                            .foregroundColor: syntaxCol,
                            .backgroundColor: codeBg,
                            .paragraphStyle:  fixedLinePS(codeLineHeight)
                        ], range: NSRange(location: openOffset, length: openLen))

                        var bodyOffset = openOffset + openLen + 1
                        for bodyLine in codeBodyLines {
                            let blen = (bodyLine as NSString).length
                            ts.addAttributes([
                                .font:            monoSmall,
                                .foregroundColor: codeColor,
                                .backgroundColor: codeBg,
                                .paragraphStyle:  fixedLinePS(codeLineHeight)
                            ], range: NSRange(location: bodyOffset, length: blen))
                            bodyOffset += blen + 1
                        }

                        // Closing fence — visible in edit mode
                        ts.addAttributes([
                            .font:            monoSmall,
                            .foregroundColor: syntaxCol,
                            .backgroundColor: codeBg,
                            .paragraphStyle:  fixedLinePS(codeLineHeight)
                        ], range: lineRange)

                    } else {
                        // ── Render mode: collapse fences, absorb into body ──
                        styleCollapsed(ts, range: NSRange(location: openOffset, length: openLen))
                        styleCollapsed(ts, range: lineRange)

                        let count      = codeBodyLines.count
                        var bodyOffset = openOffset + openLen + 1

                        for (bi, bodyLine) in codeBodyLines.enumerated() {
                            let blen = (bodyLine as NSString).length
                            var h    = codeLineHeight
                            if count == 1 {
                                h = codeLineHeight * 3 + 2  // single line absorbs both fences
                            } else {
                                if bi == 0         { h += codeLineHeight }      // absorb opening fence
                                if bi == count - 1 { h += codeLineHeight + 2 }  // absorb closing fence
                            }
                            ts.addAttributes([
                                .font:            monoSmall,
                                .foregroundColor: bg,
                                .backgroundColor: bg,
                                .paragraphStyle:  fixedLinePS(h)
                            ], range: NSRange(location: bodyOffset, length: blen))
                            bodyOffset += blen + 1
                        }

                        codeBlockInfos.append(CodeBlockInfo(
                            charRange:   blockRange,
                            lineNumbers: codeLineNums,
                            language:    codeLang,
                            codeLines:   codeBodyLines
                        ))
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

            // ── Table: classic — header row followed by separator ─────────
            if i + 1 < lines.count && isTableSeparator(lines[i + 1]) && isTableLine(line) {
                var tableLines:    [String] = [line, lines[i + 1]]
                var tableLineNums: [Int]    = [i, i + 1]
                var j = i + 2
                while j < lines.count && isTableDataLine(lines[j]) {
                    tableLines.append(lines[j]); tableLineNums.append(j); j += 1
                }
                let colCount    = columnCount(from: lines[i + 1])
                let tableOffset = offset
                var tableLen    = 0
                for tl in tableLines { tableLen += (tl as NSString).length + 1 }
                let tableRange  = NSRange(location: tableOffset, length: max(tableLen - 1, 0))
                let allRows     = tableLines
                    .filter { !isTableSeparator($0) }
                    .map    { padColumns(parseColumns($0), to: colCount) }
                tableInfos.append(TableInfo(charRange: tableRange, lineNumbers: tableLineNums,
                                            rows: allRows, hasHeader: true, colCount: colCount))
                styleTablePlaceholder(tableLines, lineNumbers: tableLineNums,
                                      startOffset: tableOffset, activeLine: activeLine,
                                      isActive: tableLineNums.contains(activeLine),
                                      hasHeader: true, in: ts)
                for tl in tableLines { offset += (tl as NSString).length + 1 }
                i = j; continue
            }

            // ── Table: headless — separator-first ────────────────────────
            else if isTableSeparator(line) {
                var tableLines:    [String] = [line]
                var tableLineNums: [Int]    = [i]
                var j = i + 1
                while j < lines.count && isTableDataLine(lines[j]) {
                    tableLines.append(lines[j]); tableLineNums.append(j); j += 1
                }
                let colCount    = columnCount(from: line)
                let tableOffset = offset
                var tableLen    = 0
                for tl in tableLines { tableLen += (tl as NSString).length + 1 }
                let tableRange  = NSRange(location: tableOffset, length: max(tableLen - 1, 0))
                let dataRows    = tableLines
                    .filter { !isTableSeparator($0) }
                    .map    { padColumns(parseColumns($0), to: colCount) }
                tableInfos.append(TableInfo(charRange: tableRange, lineNumbers: tableLineNums,
                                            rows: dataRows, hasHeader: false, colCount: colCount))
                styleTablePlaceholder(tableLines, lineNumbers: tableLineNums,
                                      startOffset: tableOffset, activeLine: activeLine,
                                      isActive: tableLineNums.contains(activeLine),
                                      hasHeader: false, in: ts)
                for tl in tableLines { offset += (tl as NSString).length + 1 }
                i = j; continue
            }

            // ── Normal line ───────────────────────────────────────────────
            if !line.isEmpty {
                if i == activeLine { styleActive(line: line, range: lineRange, in: ts) }
                else               { styleRendered(line: line, range: lineRange, in: ts) }
            }
            offset += lineLen + 1; i += 1
        }

        return (tables: tableInfos, codeBlocks: codeBlockInfos)
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
            .font:            NSFont.systemFont(ofSize: 0.001),
            .foregroundColor: bg,
            .backgroundColor: bg,
            .paragraphStyle:  ps,
            .baselineOffset:  -999
        ], range: range)
    }

    // MARK: - Table Detection

    static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        let cols = t.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cols.isEmpty else { return false }
        return cols.allSatisfy { col in
            let s = col.replacingOccurrences(of: "-", with: "")
                       .replacingOccurrences(of: ":", with: "")
                       .replacingOccurrences(of: " ", with: "")
            return s.isEmpty && col.contains("-")
        }
    }

    private static func isTableDataLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.contains("|") && !isTableSeparator(t)
    }

    private static func isTableLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.contains("|")
    }

    static func columnCount(from separator: String) -> Int {
        var cols = separator.components(separatedBy: "|")
        if cols.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cols.removeFirst() }
        if cols.last?.trimmingCharacters(in: .whitespaces).isEmpty  == true { cols.removeLast() }
        return max(cols.count, 1)
    }

    static func parseColumns(_ line: String) -> [String] {
        var cols = line.components(separatedBy: "|")
        if cols.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { cols.removeFirst() }
        if cols.last?.trimmingCharacters(in: .whitespaces).isEmpty  == true { cols.removeLast() }
        return cols.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func padColumns(_ cols: [String], to count: Int) -> [String] {
        if cols.count >= count { return Array(cols.prefix(count)) }
        return cols + Array(repeating: "", count: count - cols.count)
    }

    // MARK: - Table Placeholder

    private static func styleTablePlaceholder(
        _ tableLines: [String], lineNumbers: [Int],
        startOffset: Int, activeLine: Int,
        isActive: Bool, hasHeader: Bool,
        in ts: NSTextStorage
    ) {
        var offset   = startOffset
        var rowIndex = 0
        for line in tableLines {
            let lineLen   = (line as NSString).length
            let lineRange = NSRange(location: offset, length: lineLen)
            if isActive {
                styleActive(line: line, range: lineRange, in: ts)
            } else if isTableSeparator(line) {
                styleCollapsed(ts, range: lineRange)
            } else {
                ts.addAttributes([
                    .font: bodyFont, .foregroundColor: bg,
                    .backgroundColor: bg, .paragraphStyle: fixedLinePS(tableRowHeight)
                ], range: lineRange)
                rowIndex += 1
            }
            offset += lineLen + 1
        }
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
        rx(#"\*\*\*|\*\*|(?<!\*)\*(?!\*)|__|(?<!_)_(?!_)|~~|``?`?"#)?
            .matches(in: line, range: NSRange(location: 0, length: len)).forEach { m in
                ts.addAttribute(.foregroundColor, value: syntaxCol,
                                range: NSRange(location: loc + m.range.location, length: m.range.length))
            }
        rx(#"[\[\]\(\)]"#)?.matches(in: line, range: NSRange(location: 0, length: len)).forEach { m in
            ts.addAttribute(.foregroundColor, value: syntaxCol,
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
            ts.addAttributes([.font: NSFont.boldSystemFont(ofSize: fontSize + 15),
                              .foregroundColor: heading, .paragraphStyle: hStyle(14, 6)],
                             range: NSRange(location: loc+pl, length: range.length-pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line.hasPrefix("## "), line.count > 3 {
            let pl = 3; hide(ts, NSRange(location: loc, length: pl))
            ts.addAttributes([.font: NSFont.boldSystemFont(ofSize: fontSize + 7),
                              .foregroundColor: heading, .paragraphStyle: hStyle(10, 4)],
                             range: NSRange(location: loc+pl, length: range.length-pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line.hasPrefix("### "), line.count > 4 {
            let pl = 4; hide(ts, NSRange(location: loc, length: pl))
            ts.addAttributes([.font: NSFont.boldSystemFont(ofSize: fontSize + 2),
                              .foregroundColor: heading, .paragraphStyle: hStyle(8, 2)],
                             range: NSRange(location: loc+pl, length: range.length-pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line.hasPrefix("#### "), line.count > 5 {
            let pl = 5; hide(ts, NSRange(location: loc, length: pl))
            ts.addAttributes([.font: NSFont.boldSystemFont(ofSize: fontSize - 1), .foregroundColor: heading],
                             range: NSRange(location: loc+pl, length: range.length-pl))
            applyInlineStyles(ts, line: String(line.dropFirst(pl)), lineStart: loc+pl); return
        }
        if line.hasPrefix("> ") {
            let pl = 2; hide(ts, NSRange(location: loc, length: pl))
            let ps = NSMutableParagraphStyle()
            ps.headIndent = 18; ps.firstLineHeadIndent = 18; ps.lineSpacing = 4
            ts.addAttributes([.font: italicFont,
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
        if let m = rx(#"^(\d+\.\s)"#)?.firstMatch(in: line,
                                                    range: NSRange(location: 0, length: (line as NSString).length)) {
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

        // Inline code — collect ranges first, nothing else renders inside
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
        let showExts = UserDefaults.standard.object(forKey: "showFileExtensions") as? Bool ?? true
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
                // Optionally hide the file extension (e.g. ".pdf") in the rendered view
                if !showExts, let dotIdx = fileName.lastIndex(of: ".") {
                    let base    = fileName.distance(from: fileName.startIndex, to: dotIdx)
                    let extLen  = fileName.count - base
                    let extRange = NSRange(location: lineStart + inner.location + base, length: extLen)
                    if extRange.location + extRange.length <= ts.length { hide(ts, extRange) }
                }
            }

        // [note links] — single-bracket internal wiki links, not followed by '(' or '['
        rx(#"(?<!!)(?<!\[)\[([^\[\]\n]+)\](?!\()(?!\[)"#)?
            .matches(in: line, range: NSRange(location: 0, length: len))
            .reversed().forEach { m in
                guard !inCode(m.range) else { return }
                let absRange = NSRange(location: lineStart + m.range.location, length: m.range.length)
                guard absRange.location + absRange.length <= ts.length else { return }
                let inner = m.range(at: 1)
                let name  = ns.substring(with: inner).trimmingCharacters(in: .whitespaces)
                let slug  = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                hide(ts, NSRange(location: lineStart + m.range.location, length: 1))
                ts.addAttributes([.foregroundColor: linkColor,
                                  .link: URL(string: "mdma://note/\(slug)")!],
                                 range: NSRange(location: lineStart + inner.location, length: inner.length))
                hide(ts, NSRange(location: lineStart + inner.location + inner.length, length: 1))
            }

        if tagsOnly { return }

        // Bold-italic ***
        rx(#"\*\*\*(.+?)\*\*\*"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 3))
            ts.addAttribute(.font, value: boldItalicFont,
                            range: NSRange(location: lineStart+c.location, length: c.length))
            hide(ts, NSRange(location: lineStart+c.location+c.length, length: 3))
        }
        // Bold **
        rx(#"\*\*(.+?)\*\*"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 2))
            ts.addAttribute(.font, value: boldFont,
                            range: NSRange(location: lineStart+c.location, length: c.length))
            hide(ts, NSRange(location: lineStart+c.location+c.length, length: 2))
        }
        // Bold __
        rx(#"__(.+?)__"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 2))
            ts.addAttribute(.font, value: boldFont,
                            range: NSRange(location: lineStart+c.location, length: c.length))
            hide(ts, NSRange(location: lineStart+c.location+c.length, length: 2))
        }
        // Italic *
        rx(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 1))
            ts.addAttribute(.font, value: italicFont,
                            range: NSRange(location: lineStart+c.location, length: c.length))
            hide(ts, NSRange(location: lineStart+c.location+c.length, length: 1))
        }
        // Italic _
        rx(#"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let c = m.range(at: 1)
            hide(ts, NSRange(location: lineStart+m.range.location, length: 1))
            ts.addAttribute(.font, value: italicFont,
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
        // Images
        rx(#"!\[(.+?)\]\((.+?)\)"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            ts.addAttributes([.foregroundColor: accent.withAlphaComponent(0.7), .font: monoSmall],
                             range: NSRange(location: lineStart+m.range.location, length: m.range.length))
        }
        // Anchor links
        rx(#"(?<!!)\[(.+?)\]\(#([^)]+)\)"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let textR = m.range(at: 1); let anchorR = m.range(at: 2); let full = m.range
            hide(ts, NSRange(location: lineStart+full.location, length: 1))
            ts.addAttributes([.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue],
                             range: NSRange(location: lineStart+textR.location, length: textR.length))
            let after = textR.location + textR.length
            hide(ts, NSRange(location: lineStart+after, length: full.location+full.length-after))
            if let anchor = Range(anchorR, in: line).map({ String(line[$0]) }),
               let url = URL(string: "mdma://anchor/\(anchor.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? anchor)") {
                ts.addAttribute(.link, value: url, range: NSRange(location: lineStart+textR.location, length: textR.length))
            }
        }
        // Cross-file links
        rx(#"(?<!!)\[(.+?)\]\((mdma://[^)]+)\)"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let textR = m.range(at: 1); let urlR = m.range(at: 2); let full = m.range
            hide(ts, NSRange(location: lineStart+full.location, length: 1))
            ts.addAttributes([.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue],
                             range: NSRange(location: lineStart+textR.location, length: textR.length))
            let after = textR.location + textR.length
            hide(ts, NSRange(location: lineStart+after, length: full.location+full.length-after))
            if let urlStr = Range(urlR, in: line).map({ String(line[$0]) }), let url = URL(string: urlStr) {
                ts.addAttribute(.link, value: url, range: NSRange(location: lineStart+textR.location, length: textR.length))
            }
        }
        // Standard links
        rx(#"(?<!!)\[(.+?)\]\((?!#)(?!mdma)(.+?)\)"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let textR = m.range(at: 1); let urlR = m.range(at: 2); let full = m.range
            hide(ts, NSRange(location: lineStart+full.location, length: 1))
            ts.addAttributes([.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue],
                             range: NSRange(location: lineStart+textR.location, length: textR.length))
            let after = textR.location + textR.length
            hide(ts, NSRange(location: lineStart+after, length: full.location+full.length-after))
            if let urlStr = Range(urlR, in: line).map({ String(line[$0]) }) {
                let withScheme = urlStr.hasPrefix("www.") ? "https://\(urlStr)" : urlStr
                if let url = URL(string: withScheme) {
                    ts.addAttribute(.link, value: url, range: NSRange(location: lineStart+textR.location, length: textR.length))
                }
            }
        }
        // Reverse links
        rx(#"\(((?:https?://|www\.)[^\s\)]+)\)\(([^)]+)\)"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            let urlR = m.range(at: 1); let textR = m.range(at: 2); let full = m.range
            hide(ts, NSRange(location: lineStart+full.location, length: urlR.length+3))
            ts.addAttributes([.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue],
                             range: NSRange(location: lineStart+textR.location, length: textR.length))
            hide(ts, NSRange(location: lineStart+textR.location+textR.length, length: 1))
            if let urlStr = Range(urlR, in: line).map({ String(line[$0]) }) {
                let withScheme = urlStr.hasPrefix("www.") ? "https://\(urlStr)" : urlStr
                if let url = URL(string: withScheme) {
                    ts.addAttribute(.link, value: url, range: NSRange(location: lineStart+textR.location, length: textR.length))
                }
            }
        }
        // Bare URLs
        rx(#"(?<!\()(?:https?://|www\.)[^\s\)<]+"#)?.matches(in: line, range: NSRange(location: 0, length: len)).reversed().forEach { m in
            guard !inCode(m.range) else { return }
            guard ts.attribute(.link, at: lineStart+m.range.location, effectiveRange: nil) == nil else { return }
            let urlStr = ns.substring(with: m.range)
            let withScheme = urlStr.hasPrefix("www.") ? "https://\(urlStr)" : urlStr
            if let url = URL(string: withScheme) {
                ts.addAttributes([.foregroundColor: linkColor,
                                  .underlineStyle:  NSUnderlineStyle.single.rawValue,
                                  .link:            url],
                                 range: NSRange(location: lineStart+m.range.location, length: m.range.length))
            }
        }
    }

    // MARK: - Shared Helpers

    private static func hide(_ ts: NSTextStorage, _ range: NSRange) {
        guard range.location != NSNotFound, range.length > 0,
              range.location + range.length <= ts.length else { return }
        ts.addAttributes([.font: NSFont.systemFont(ofSize: 0.001), .foregroundColor: bg], range: range)
    }

    private static func hStyle(_ before: CGFloat, _ after: CGFloat) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacingBefore = before; ps.paragraphSpacing = after; ps.lineSpacing = 2
        return ps
    }

    private static func rx(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }
}
