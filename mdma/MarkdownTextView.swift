import AppKit
import Contacts

// MARK: - Vim Mode

enum VimMode { case normal, insert, visual }

class MarkdownTextView: NSTextView {

    var onTextChange:     ((String) -> Void)?
    var onSelectionChange: ((String) -> Void)?   // passes selected text (empty if no selection)
    private var activeLine   = 0
    private var isStyling    = false
    private var isLoading    = false

    // Vim
    private var vimMode:          VimMode = .insert
    private var visualAnchor:     Int     = 0
    private var pendingD:         Bool    = false   // waiting for second 'd' in "dd"

    // Code folding — set of 0-based opening fence line numbers for explicitly folded blocks
    private var foldedBlockLines: Set<Int> = []

    // Contact popover
    private var contactPanel: NSPanel?
    private var atSignRange:  NSRange?

    // File-link picker ([note] syntax)
    private var fileLinkPanel: NSPanel?
    private var bracketRange:  NSRange?

    // Table and Code overlays
    private var codeOverlays:    [CodeBlockOverlayView] = []
    private var tableOverlays:   [TableOverlayView]     = []
    private var tableInfos:      [TableInfo]             = []
    private var codeBlockInfos:  [CodeBlockInfo]         = []

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    
    @objc private func handleInsertText(_ note: Notification) {
        guard let text = note.object as? String,
              window?.firstResponder == self else { return }
        let sel = selectedRange()
        if let ts = textStorage {
            ts.replaceCharacters(in: sel, with: text)
            setSelectedRange(NSRange(location: sel.location + (text as NSString).length, length: 0))
            restyle(currentLine())
            onTextChange?(string)
        }
    }

    private func setup() {
        backgroundColor                      = MarkdownParser.bg
        insertionPointColor                  = MarkdownParser.accent
        selectedTextAttributes               = [.backgroundColor: MarkdownParser.accent.withAlphaComponent(0.25)]
        isRichText                           = false
        allowsUndo                           = true
        isAutomaticQuoteSubstitutionEnabled  = false
        isAutomaticDashSubstitutionEnabled   = false
        isAutomaticTextReplacementEnabled    = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled     = false
        textContainerInset                   = NSSize(width: 72, height: 52)
        typingAttributes                     = MarkdownParser.defaultAttrs()
        linkTextAttributes                   = [:]

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInsertText(_:)),
            name: .insertText, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScrollToLine(_:)),
            name: .scrollToLine, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange),
            name: .themeDidChange, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleVimModeSettingChange),
            name: .vimModeSettingChanged, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSpellCheckSettingChange),
            name: .spellCheckChanged, object: nil)

        // Find / Replace
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFindSearch(_:)),
            name: .findBarSearch, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFindNext),
            name: .findBarNext, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFindPrev),
            name: .findBarPrev, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleReplaceOne(_:)),
            name: .findBarReplaceOne, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleReplaceAll(_:)),
            name: .findBarReplaceAll, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleFindClear),
            name: .findBarClear, object: nil)

        // Apply persisted spell-check preference
        let spellOn = UserDefaults.standard.bool(forKey: "spellCheck")
        isContinuousSpellCheckingEnabled = spellOn
    }

    @objc private func handleVimModeSettingChange() {
        let enabled = UserDefaults.standard.bool(forKey: "vimMode")
        vimMode = enabled ? .normal : .insert
        pendingD = false
        needsDisplay = true
    }

    @objc private func handleSpellCheckSettingChange() {
        let spellOn = UserDefaults.standard.bool(forKey: "spellCheck")
        isContinuousSpellCheckingEnabled = spellOn
    }

    @objc private func handleThemeChange() {
        backgroundColor         = MarkdownParser.bg
        insertionPointColor     = MarkdownParser.accent
        selectedTextAttributes  = [.backgroundColor: MarkdownParser.accent.withAlphaComponent(0.25)]
        typingAttributes        = MarkdownParser.defaultAttrs()
        enclosingScrollView?.backgroundColor = MarkdownParser.bg
        restyle(activeLine)
        needsDisplay = true
    }

    // MARK: - Find / Replace

    private var findMatchRanges: [NSRange] = []
    private var findMatchIndex:  Int       = -1  // index into findMatchRanges of current selection
    private var findQuery:       String    = ""
    private var findMatchCase:   Bool      = false

    private static let findHighlight  = NSColor.systemYellow.withAlphaComponent(0.45)
    private static let findCurrentHL  = NSColor.systemOrange.withAlphaComponent(0.55)

    @objc private func handleFindSearch(_ note: Notification) {
        let q         = (note.userInfo?["query"] as? String) ?? ""
        let matchCase = (note.userInfo?["matchCase"] as? Bool) ?? false
        findQuery     = q
        findMatchCase = matchCase
        clearFindHighlights()
        guard !q.isEmpty, let lm = layoutManager else {
            postFindCount(0, index: 0); return
        }
        let opts: NSString.CompareOptions = matchCase ? [.literal] : [.caseInsensitive]
        let ns   = string as NSString
        var searchRange = NSRange(location: 0, length: ns.length)
        var ranges: [NSRange] = []
        while searchRange.location < ns.length {
            let r = ns.range(of: q, options: opts, range: searchRange)
            guard r.location != NSNotFound else { break }
            ranges.append(r)
            lm.addTemporaryAttribute(.backgroundColor,
                                      value: MarkdownTextView.findHighlight,
                                      forCharacterRange: r)
            searchRange = NSRange(location: r.upperBound,
                                  length: ns.length - r.upperBound)
        }
        findMatchRanges = ranges
        // Set current match to closest to current cursor
        if ranges.isEmpty {
            findMatchIndex = -1
            postFindCount(0, index: 0)
        } else {
            let cursor = selectedRange().location
            let best   = ranges.enumerated().min(by: { abs($0.element.location - cursor) < abs($1.element.location - cursor) })?.offset ?? 0
            findMatchIndex = best
            highlightCurrentMatch()
            scrollTo(ranges[best])
            postFindCount(ranges.count, index: best + 1)
        }
    }

    @objc private func handleFindNext() {
        guard !findMatchRanges.isEmpty else { return }
        findMatchIndex = (findMatchIndex + 1) % findMatchRanges.count
        highlightCurrentMatch()
        scrollTo(findMatchRanges[findMatchIndex])
        setSelectedRange(findMatchRanges[findMatchIndex])
        postFindCount(findMatchRanges.count, index: findMatchIndex + 1)
    }

    @objc private func handleFindPrev() {
        guard !findMatchRanges.isEmpty else { return }
        findMatchIndex = (findMatchIndex - 1 + findMatchRanges.count) % findMatchRanges.count
        highlightCurrentMatch()
        scrollTo(findMatchRanges[findMatchIndex])
        setSelectedRange(findMatchRanges[findMatchIndex])
        postFindCount(findMatchRanges.count, index: findMatchIndex + 1)
    }

    @objc private func handleReplaceOne(_ note: Notification) {
        guard !findMatchRanges.isEmpty,
              findMatchIndex >= 0, findMatchIndex < findMatchRanges.count,
              let rep = note.userInfo?["replacement"] as? String,
              let ts  = textStorage else { return }
        let range = findMatchRanges[findMatchIndex]
        guard shouldChangeText(in: range, replacementString: rep) else { return }
        ts.replaceCharacters(in: range, with: rep)
        didChangeText()
        onTextChange?(string)
        // Re-run search after replacement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let fakeNote = Notification(name: .findBarSearch, object: nil,
                                        userInfo: ["query": self.findQuery, "matchCase": self.findMatchCase])
            self.handleFindSearch(fakeNote)
        }
    }

    @objc private func handleReplaceAll(_ note: Notification) {
        guard !findQuery.isEmpty,
              let rep = note.userInfo?["replacement"] as? String,
              let ts  = textStorage else { return }
        let opts: NSString.CompareOptions = findMatchCase ? [.literal] : [.caseInsensitive]
        // Collect ranges right to left so indices don't shift
        let ns     = string as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: ns.length)
        while searchRange.location < ns.length {
            let r = ns.range(of: findQuery, options: opts, range: searchRange)
            guard r.location != NSNotFound else { break }
            ranges.append(r)
            searchRange = NSRange(location: r.upperBound, length: ns.length - r.upperBound)
        }
        guard !ranges.isEmpty,
              shouldChangeText(in: NSRange(location: 0, length: ts.length), replacementString: nil)
        else { return }
        ts.beginEditing()
        for r in ranges.reversed() {
            ts.replaceCharacters(in: r, with: rep)
        }
        ts.endEditing()
        didChangeText()
        onTextChange?(string)
        clearFindHighlights()
        findMatchRanges = []
        postFindCount(0, index: 0)
    }

    @objc private func handleFindClear() {
        clearFindHighlights()
        findMatchRanges = []
        findMatchIndex  = -1
        findQuery       = ""
    }

    private func clearFindHighlights() {
        guard let lm = layoutManager else { return }
        let full = NSRange(location: 0, length: (string as NSString).length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
    }

    private func highlightCurrentMatch() {
        guard let lm = layoutManager else { return }
        // Re-paint all matches in background colour
        for (i, r) in findMatchRanges.enumerated() {
            let col = (i == findMatchIndex)
                ? MarkdownTextView.findCurrentHL
                : MarkdownTextView.findHighlight
            lm.addTemporaryAttribute(.backgroundColor, value: col, forCharacterRange: r)
        }
    }

    private func scrollTo(_ range: NSRange) {
        scrollRangeToVisible(range)
    }

    private func postFindCount(_ count: Int, index: Int) {
        NotificationCenter.default.post(
            name: .findBarUpdateCount, object: nil,
            userInfo: ["count": count, "index": index])
    }

    // MARK: - Load / Restyle

    func load(_ text: String) {
        isLoading = true; string = text; isLoading = false
        restyle(currentLine())
    }
    
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layout = layoutManager, let container = textContainer else { return }

        let hrColor = NSColor(srgbRed: 0.28, green: 0.28, blue: 0.32, alpha: 1)
        let lines   = string.components(separatedBy: "\n")
        var offset  = 0

        for (lineNum, line) in lines.enumerated() {
            let len = (line as NSString).length
            if (line == "---" || line == "***" || line == "___") && lineNum != activeLine {
                let glyphRange = layout.glyphRange(
                    forCharacterRange: NSRange(location: offset, length: max(len, 1)),
                    actualCharacterRange: nil
                )
                var lineRect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
                lineRect.origin.x += textContainerInset.width
                lineRect.origin.y += textContainerInset.height

                let barY = lineRect.midY
                let barX = textContainerInset.width
                let barW = frame.width - textContainerInset.width * 2

                hrColor.setFill()
                NSRect(x: barX, y: barY - 0.5, width: barW, height: 1).fill()
            }
            offset += len + 1
        }
    }
    
    override func didChangeText() {
        super.didChangeText()
        guard !isLoading, !isStyling else { return }
        let line = currentLine(); activeLine = line
        restyle(line)
        onTextChange?(string)
        checkForAtTrigger()
        checkForBracketTrigger()
    }

    func cursorMoved() {
        // Always fire selection change so word count stays current
        let sel = selectedRange()
        let selectedText = sel.length > 0 ? ((string as NSString).substring(with: sel)) : ""
        onSelectionChange?(selectedText)

        let line = currentLine()
        guard line != activeLine else { return }
        activeLine = line
        restyle(line)
    }

    private func restyle(_ line: Int) {
        guard !isStyling, let ts = textStorage else { return }
        isStyling = true
        let saved    = selectedRanges
        let text     = ts.string
        ts.beginEditing()
        let result   = MarkdownParser.applyStyle(to: ts, activeLine: line)
        // Code block folding
        let allLines = text.components(separatedBy: "\n")
        for block in result.codeBlocks {
            let fenceLineNum = block.lineNumbers.first ?? 0
            if foldedBlockLines.contains(fenceLineNum) {
                applyFoldedAttributes(for: block, in: allLines)
            }
        }
        ts.endEditing()
        selectedRanges   = saved
        typingAttributes = MarkdownParser.defaultAttrs()
        isStyling = false

        // Update overlays after layout has settled
        DispatchQueue.main.async { [weak self] in
            self?.tableInfos     = result.tables
            self?.codeBlockInfos = result.codeBlocks
            self?.updateTableOverlays(tables: result.tables)
            self?.updateCodeOverlays(codeBlocks: result.codeBlocks)
        }
    }

    // MARK: - Code Overlays
    private func updateCodeOverlays(codeBlocks: [CodeBlockInfo]) {
        codeOverlays.forEach { $0.removeFromSuperview() }
        codeOverlays = []

        guard let layout = layoutManager, let container = textContainer else { return }
        layout.ensureLayout(for: container)

        let inset    = textContainerInset
        let cursor   = selectedRange().location
        let allLines = string.components(separatedBy: "\n")

        for block in codeBlocks {
            let fenceLineNum  = block.lineNumbers.first ?? 0
            let isFolded      = foldedBlockLines.contains(fenceLineNum)

            // Show raw if cursor is inside and NOT folded
            let cursorInBlock = cursor >= block.charRange.location &&
                                cursor <= block.charRange.location + block.charRange.length
            if cursorInBlock && !isFolded { continue }

            guard !block.codeLines.isEmpty else { continue }

            // Find y position — use opening fence line (not first body) so overlay sits flush
            let anchorLine = isFolded ? fenceLineNum : fenceLineNum + 1
            guard anchorLine < allLines.count else { continue }

            var anchorOffset = 0
            for (idx, line) in allLines.enumerated() {
                if idx == anchorLine { break }
                anchorOffset += (line as NSString).length + 1
            }
            guard anchorOffset <= string.utf16.count else { continue }

            let glyph    = layout.glyphIndexForCharacter(at: anchorOffset)
            let fragRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let x        = inset.width
            let y        = fragRect.origin.y + inset.height + (isFolded ? fragRect.height : 0)

            // Build overlay
            let overlay       = CodeBlockOverlayView()
            overlay.codeLines = block.codeLines
            overlay.language  = block.language
            overlay.isFolded  = isFolded

            let w = max(bounds.width - inset.width * 2, 200)
            let h = overlay.preferredHeight
            overlay.frame = NSRect(x: x, y: y, width: w, height: h)

            overlay.onTap = { [weak self] in
                guard let self else { return }
                self.setSelectedRange(NSRange(location: block.charRange.location, length: 0))
                let line = self.currentLine()
                self.activeLine = line
                self.restyle(line)
            }

            overlay.onFoldToggle = { [weak self] in
                guard let self else { return }
                if self.foldedBlockLines.contains(fenceLineNum) {
                    self.foldedBlockLines.remove(fenceLineNum)
                } else {
                    self.foldedBlockLines.insert(fenceLineNum)
                }
                self.restyle(self.activeLine)
            }

            addSubview(overlay)
            codeOverlays.append(overlay)
        }
    }

    /// Apply near-zero font + clear color to body lines of a folded block so they take no visual space.
    private func applyFoldedAttributes(for block: CodeBlockInfo, in allLines: [String]) {
        guard let ts = textStorage, block.lineNumbers.count >= 2 else { return }
        let tinyFont = NSFont.systemFont(ofSize: 0.001)
        let ps       = NSMutableParagraphStyle()
        ps.maximumLineHeight = 0.1
        ps.minimumLineHeight = 0.1
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            tinyFont,
            .foregroundColor: NSColor.clear,
            .paragraphStyle:  ps
        ]
        // Collapse all lines from the first body line to the closing fence (inclusive)
        let firstBodyLine  = block.lineNumbers[0] + 1
        let closingLine    = block.lineNumbers.last!
        guard firstBodyLine <= closingLine else { return }

        var startOffset = 0
        var endOffset   = 0
        var foundStart  = false
        var foundEnd    = false
        var charOffset  = 0
        for (i, line) in allLines.enumerated() {
            let lineLen = (line as NSString).length + 1
            if i == firstBodyLine  { startOffset = charOffset; foundStart = true }
            if i == closingLine    { endOffset   = charOffset + (line as NSString).length; foundEnd = true; break }
            charOffset += lineLen
        }
        guard foundStart, foundEnd, endOffset > startOffset else { return }
        let range = NSRange(location: startOffset, length: endOffset - startOffset)
        guard range.location + range.length <= ts.length else { return }
        ts.addAttributes(attrs, range: range)
    }


    // MARK: - Table Overlays

    private func updateTableOverlays(tables: [TableInfo]) {
        tableOverlays.forEach { $0.removeFromSuperview() }
        tableOverlays = []

        guard let layout = layoutManager, let container = textContainer else { return }
        layout.ensureLayout(for: container)

        let inset  = textContainerInset
        let cursor = selectedRange().location
        let allLines = string.components(separatedBy: "\n")

        for table in tables {
            let tRange = table.charRange

            // Skip — show raw when cursor is inside this table
            let cursorInTable = cursor >= tRange.location &&
                                cursor <= tRange.location + tRange.length
            if cursorInTable { continue }

            guard tRange.location <= string.utf16.count else { continue }

            // ── Measure each line's actual rendered height ─────────────────
            // Walk all line numbers, collect heights for separator and data lines separately
            var lineHeightMap: [Int: CGFloat] = [:]  // lineNumber → rendered height
            var charOffset = 0

            for (idx, line) in allLines.enumerated() {
                let lineLen = (line as NSString).length
                if table.lineNumbers.contains(idx) {
                    let glyphIdx = layout.glyphIndexForCharacter(at: charOffset)
                    let fragRect = layout.lineFragmentRect(forGlyphAt: glyphIdx,
                                                           effectiveRange: nil)
                    lineHeightMap[idx] = fragRect.height
                }
                charOffset += lineLen + 1
                if charOffset > string.utf16.count { break }
            }

            // ── Build per-row heights ──────────────────────────────────────
            // For headed tables: header row absorbs the separator height
            // For headless tables: separator is just gone (height ~0)
            var rowHeights: [CGFloat] = []
            let dataLineNums = table.lineNumbers.filter {
                $0 < allLines.count && !MarkdownParser.isTableSeparator(allLines[$0])
            }
            let sepLineNums = table.lineNumbers.filter {
                $0 < allLines.count && MarkdownParser.isTableSeparator(allLines[$0])
            }
            let sepHeight = sepLineNums.compactMap { lineHeightMap[$0] }.reduce(0, +)

            if table.hasHeader {
                // Header absorbs the separator line height
                for (ri, lineNum) in dataLineNums.enumerated() {
                    var h = lineHeightMap[lineNum] ?? MarkdownParser.tableRowHeight
                    if ri == 0 { h += sepHeight }
                    rowHeights.append(h)
                }
            } else {
                // Headless: all rows get the same height = average + even share of separator
                let rawHeights = dataLineNums.map { lineHeightMap[$0] ?? MarkdownParser.tableRowHeight }
                let avgHeight  = rawHeights.reduce(0, +) / CGFloat(max(rawHeights.count, 1))
                let extraPerRow = sepHeight / CGFloat(max(dataLineNums.count, 1))
                let uniformH   = avgHeight + extraPerRow
                rowHeights = Array(repeating: uniformH, count: dataLineNums.count)
            }

            guard !rowHeights.isEmpty else { continue }

            // ── Position overlay ───────────────────────────────────────────
            // Y = top of the first data line
            guard let firstDataLine = dataLineNums.first else { continue }
            var firstCharOffset = 0
            for (idx, line) in allLines.enumerated() {
                if idx == firstDataLine { break }
                firstCharOffset += (line as NSString).length + 1
            }
            guard firstCharOffset <= string.utf16.count else { continue }

            let firstGlyph = layout.glyphIndexForCharacter(at: firstCharOffset)
            let fragRect   = layout.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)

            let x      = inset.width
            let y      = fragRect.origin.y + inset.height
            let w      = max(bounds.width - inset.width * 2, 100)
            let totalH = rowHeights.reduce(0, +)

            let frame   = NSRect(x: x, y: y, width: w, height: totalH)
            let overlay = TableOverlayView(frame: frame)
            overlay.rows       = table.rows
            overlay.rowHeights = rowHeights
            overlay.hasHeader  = table.hasHeader
            overlay.colCount   = table.colCount
            overlay.onTap      = { [weak self] in
                guard let self else { return }
                self.setSelectedRange(NSRange(location: tRange.location, length: 0))
                let line = self.currentLine()
                self.activeLine = line
                self.restyle(line)
            }

            addSubview(overlay)
            tableOverlays.append(overlay)
        }
    }

    // MARK: - Resize

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTableOverlays(tables: tableInfos)
        updateCodeOverlays(codeBlocks: codeBlockInfos)
    }

    // MARK: - Current Line

    private func currentLine() -> Int {
        let pt  = selectedRange().location
        let ns  = string as NSString
        var line = 0
        var n    = 0
        while n < pt {
            if n < ns.length && ns.character(at: n) == 10 { // '\n'
                line += 1
            }
            n += 1
        }
        // If cursor is sitting right before a \n (end of line),
        // treat it as still on this line, not the next
        return line
    }
    // MARK: - Auto-close and wrap

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let insertion = (string as? String) ?? ""
        let sel       = selectedRange()

        // Wrapping: if text is selected, wrap instead of replace
        if sel.length > 0, let ts = textStorage {
            let selected = (self.string as NSString).substring(with: sel)
            let wrapped: String?
            switch insertion {
            case "$":  wrapped = "$\(selected)$"
            case "@":  wrapped = "@\(selected)@"
            case "(":  wrapped = "(\(selected))"
            case "[":  wrapped = "[\(selected)]"
            case "{":  wrapped = "{\(selected)}"
            case "<":  wrapped = "<\(selected)>"
            case "|":  wrapped = "|\(selected)|"
            default:   wrapped = nil
            }
            if let w = wrapped {
                ts.replaceCharacters(in: sel, with: w)
                setSelectedRange(NSRange(location: sel.location + (w as NSString).length, length: 0))
                restyle(currentLine())
                onTextChange?(self.string)
                return
            }
        }

        // Auto-close pairs
        let pairs: [String: String] = [
            "(": ")", "[": "]", "{": "}", "<": ">"
        ]

        if sel.length == 0, let closing = pairs[insertion] {
            // Skip if next char is already the closing char
            let pos = sel.location
            let ns  = self.string as NSString
            if pos < ns.length {
                let next = String(UnicodeScalar(ns.character(at: pos))!)
                if next == closing {
                    setSelectedRange(NSRange(location: pos + 1, length: 0))
                    return
                }
            }
            super.insertText("\(insertion)\(closing)", replacementRange: sel)
            setSelectedRange(NSRange(location: pos + insertion.utf16.count, length: 0))
            restyle(currentLine()); onTextChange?(self.string)
            if insertion == "[" { checkForBracketTrigger() }
            return
        }

        if insertion == "@" && sel.length == 0 {
            super.insertText("@", replacementRange: sel)
            restyle(currentLine()); onTextChange?(self.string)
            checkForAtTrigger(); return
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0 && sel.location > 0, let ts = textStorage {
            let ns   = self.string as NSString
            let prev = String(UnicodeScalar(ns.character(at: sel.location - 1))!)
            let pairs: [String: String] = [
                "(": ")", "[": "]", "{": "}", "<": ">", "$": "$", "@": "@"
            ]
            if let closing = pairs[prev], sel.location < ns.length {
                let next = String(UnicodeScalar(ns.character(at: sel.location))!)
                if next == closing {
                    ts.replaceCharacters(in: NSRange(location: sel.location - 1, length: 2), with: "")
                    setSelectedRange(NSRange(location: sel.location - 1, length: 0))
                    restyle(currentLine()); onTextChange?(self.string); return
                }
            }
        }
        super.deleteBackward(sender)
    }

    // MARK: - Paste with file-reference detection

    override func paste(_ sender: Any?) {
        let pb  = NSPasteboard.general
        let sel = selectedRange()
        let ns  = string as NSString

        // If cursor is immediately after a lone | and the pasteboard has file URLs,
        // import the file as a reference and auto-close the pair.
        let prevIsBar = sel.length == 0 &&
                        sel.location > 0 &&
                        String(UnicodeScalar(ns.character(at: sel.location - 1))!) == "|"

        if prevIsBar,
           let items = pb.readObjects(forClasses: [NSURL.self],
                                      options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let fileURL = items.first {
            if let name = FileSystemManager.shared.addFileReference(fileURL) {
                let openBar = NSRange(location: sel.location - 1, length: 1)
                if let ts = textStorage {
                    let insert = "|\(name)|"
                    ts.replaceCharacters(in: openBar, with: insert)
                    setSelectedRange(NSRange(location: openBar.location + (insert as NSString).length, length: 0))
                    restyle(currentLine())
                    onTextChange?(self.string)
                }
            }
            return
        }

        super.paste(sender)
    }

    // MARK: - @ Contact Picker

    private func checkForAtTrigger() {
        let cursor = selectedRange().location
        guard cursor > 0 else { dismissContactPopover(); return }
        let full = string
        guard let cursorPos = full.utf16.index(
            full.utf16.startIndex, offsetBy: min(cursor, full.utf16.count)
        ).samePosition(in: full) else { dismissContactPopover(); return }

        var idx = full.index(before: cursorPos)
        while true {
            let ch = full[idx]
            if ch == "@" {
                let isBoundary = idx == full.startIndex ||
                    { let p = full[full.index(before: idx)]; return p == " " || p == "\n" || p == "\t" }()
                if isBoundary {
                    let afterAt = full.index(after: idx)
                    let query   = afterAt <= cursorPos ? String(full[afterAt..<cursorPos]) : ""
                    if !query.contains(" ") && !query.contains("\n") {
                        let loc = full.utf16.distance(from: full.utf16.startIndex,
                                                       to: idx.samePosition(in: full.utf16) ?? full.utf16.startIndex)
                        atSignRange = NSRange(location: loc, length: cursor - loc)
                        showContactPopover(query: query); return
                    }
                }
                break
            }
            if ch == " " || ch == "\n" || ch == "\t" { break }
            if idx == full.startIndex { break }
            idx = full.index(before: idx)
        }
        dismissContactPopover()
    }

    private func showContactPopover(query: String) {
        guard ContactsManager.shared.authorized else {
            ContactsManager.shared.requestAccess(); return
        }
        let contacts = ContactsManager.shared.search(query.isEmpty ? "a" : query)
        if contacts.isEmpty && !query.isEmpty { dismissContactPopover(); return }

        if contactPanel == nil {
            let panel       = ContactPickerPanel()
            panel.onSelect  = { [weak self] c in self?.insertContact(c) }
            panel.onDismiss = { [weak self] in self?.dismissContactPopover() }
            contactPanel    = panel
        }
        (contactPanel as? ContactPickerPanel)?.update(contacts: contacts)

        if let panel = contactPanel as? ContactPickerPanel, !panel.isVisible,
           let rect = rectForCursor(), let win = window {
            var sr = convert(rect, to: nil)
            sr = win.convertToScreen(sr)
            sr.origin.y -= panel.frame.height + 4
            sr.origin.x -= 10
            panel.setFrameOrigin(sr.origin)
            panel.orderFront(nil)
        }
    }

    func dismissContactPopover() {
        (contactPanel as? ContactPickerPanel)?.orderOut(nil)
        contactPanel = nil
        atSignRange  = nil
    }

    private func insertContact(_ contact: CNContact) {
        guard let range = atSignRange else { dismissContactPopover(); return }
        let name   = ContactsManager.shared.displayName(contact)
        let insert = "@\(name)@"
        if let ts = textStorage {
            ts.replaceCharacters(in: range, with: insert)
            setSelectedRange(NSRange(location: range.location + (insert as NSString).length, length: 0))
            restyle(currentLine())
            onTextChange?(string)
        }
        dismissContactPopover()
        window?.makeFirstResponder(self)
    }

    private func rectForCursor() -> NSRect? {
        guard let layout = layoutManager, let container = textContainer else { return nil }
        let cursor = selectedRange().location
        guard cursor > 0 else { return nil }
        let glyph  = layout.glyphIndexForCharacter(at: cursor - 1)
        var rect   = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        return rect
    }

    // MARK: - [ File Link Picker

    private func checkForBracketTrigger() {
        let cursor = selectedRange().location
        guard cursor > 0 else { dismissFileLinkPicker(); return }
        let full = string
        guard let cursorPos = full.utf16.index(
            full.utf16.startIndex, offsetBy: min(cursor, full.utf16.count)
        ).samePosition(in: full) else { dismissFileLinkPicker(); return }

        // Never trigger inside a fenced code block
        let inCodeBlock = codeBlockInfos.contains {
            cursor >= $0.charRange.location && cursor < $0.charRange.location + $0.charRange.length
        }
        if inCodeBlock { dismissFileLinkPicker(); return }

        // Walk back from cursor looking for an opening '['
        var idx = full.index(before: cursorPos)
        while true {
            let ch = full[idx]
            if ch == "[" {
                // Ignore [[ (the old double-bracket syntax — shouldn't appear, but guard anyway)
                let beforeBracket = idx > full.startIndex ? full[full.index(before: idx)] : " "
                if beforeBracket == "[" { dismissFileLinkPicker(); return }
                let afterBracket = full.index(after: idx)
                let query = afterBracket <= cursorPos ? String(full[afterBracket..<cursorPos]) : ""
                // Stop if the query already contains a closing bracket (link was completed)
                if query.contains("]") { dismissFileLinkPicker(); return }
                let loc = full.utf16.distance(from: full.utf16.startIndex,
                                               to: idx.samePosition(in: full.utf16) ?? full.utf16.startIndex)
                bracketRange = NSRange(location: loc, length: cursor - loc)
                showFileLinkPicker(query: query)
                return
            }
            // Stop scanning at line breaks or closing brackets
            if ch == "]" || ch == "\n" { break }
            if idx == full.startIndex { break }
            idx = full.index(before: idx)
        }
        dismissFileLinkPicker()
    }

    private func showFileLinkPicker(query: String) {
        let fsm = FileSystemManager.shared
        let all = fsm.allNoteURLs

        if fileLinkPanel == nil {
            let panel       = FileLinkPickerPanel()
            panel.onSelect  = { [weak self] name in self?.insertFileLink(name: name) }
            panel.onDismiss = { [weak self] in self?.dismissFileLinkPicker() }
            fileLinkPanel   = panel
        }
        (fileLinkPanel as? FileLinkPickerPanel)?.update(
            allFiles: all, query: query, rootURL: fsm.rootURL)

        if let panel = fileLinkPanel as? FileLinkPickerPanel, !panel.isVisible,
           let rect = rectForCursor(), let win = window {
            var sr = convert(rect, to: nil)
            sr = win.convertToScreen(sr)
            sr.origin.y -= panel.frame.height + 4
            sr.origin.x -= 10
            panel.setFrameOrigin(sr.origin)
            panel.orderFront(nil)
        }
    }

    func dismissFileLinkPicker() {
        (fileLinkPanel as? FileLinkPickerPanel)?.orderOut(nil)
        fileLinkPanel = nil
        bracketRange  = nil
    }

    private func insertFileLink(name: String) {
        guard let range = bracketRange else { dismissFileLinkPicker(); return }
        let ns     = string as NSString
        let cursor = selectedRange().location
        // Include the auto-close ']' if it sits immediately after the cursor
        let end: Int = (cursor < ns.length && ns.character(at: cursor) == 93) ? cursor + 1 : cursor
        let fullRange = NSRange(location: range.location, length: end - range.location)
        let insert    = "[\(name)]"
        if let ts = textStorage {
            ts.replaceCharacters(in: fullRange, with: insert)
            setSelectedRange(NSRange(location: range.location + (insert as NSString).length, length: 0))
            restyle(currentLine())
            onTextChange?(string)
        }
        dismissFileLinkPicker()
        window?.makeFirstResponder(self)
    }

    // MARK: - Key routing for contact panel

    override func keyDown(with event: NSEvent) {
        if let panel = contactPanel as? ContactPickerPanel, panel.isVisible {
            switch event.keyCode {
            case 125: panel.moveDown();        return
            case 126: panel.moveUp();          return
            case 36:  panel.selectCurrent();   return
            case 53:  dismissContactPopover(); return
            default:  break
            }
        }

        if let panel = fileLinkPanel as? FileLinkPickerPanel, panel.isVisible {
            switch event.keyCode {
            case 125: panel.moveDown();         return
            case 126: panel.moveUp();           return
            case 36:  panel.selectCurrent();    return
            case 53:  dismissFileLinkPicker();  return
            default:  break
            }
        }

        // Route through vim handler when vim mode is on
        let vimEnabled = UserDefaults.standard.bool(forKey: "vimMode")
        if vimEnabled, handleVimKey(event) { return }

        super.keyDown(with: event)
    }

    // MARK: - Vim Key Handler
    // Returns true if the event was consumed.
    @discardableResult
    private func handleVimKey(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        let mods  = event.modifierFlags

        // Esc always exits to Normal (in any mode)
        if event.keyCode == 53 {
            if vimMode != .normal {
                vimMode  = .insert   // briefly set to insert so we don't mess up
                vimMode  = .normal
                pendingD = false
                // Collapse selection to cursor start
                let loc = selectedRange().location
                setSelectedRange(NSRange(location: loc, length: 0))
                needsDisplay = true
            }
            return true
        }

        switch vimMode {

        case .insert:
            // In insert mode we only intercept Esc (handled above). Everything else is normal.
            return false

        case .normal:
            // No modifier keys for single-char commands (allow Shift for $, ^ etc.)
            let noCtrl = !mods.contains(.control) && !mods.contains(.command) && !mods.contains(.option)
            guard noCtrl, chars.count == 1 else { return false }
            let ch = chars

            // "dd" — delete whole line
            if ch == "d" {
                if pendingD {
                    pendingD = false
                    deleteCurrentLine(); return true
                }
                pendingD = true
                return true
            }
            pendingD = false

            switch ch {
            case "i":
                vimMode = .insert; needsDisplay = true; return true
            case "I":
                vimMode = .insert
                moveToBeginningOfLine(nil); needsDisplay = true; return true
            case "a":
                vimMode = .insert
                // Move one right unless at EOL
                let ns  = string as NSString
                let pos = selectedRange().location
                if pos < ns.length {
                    let c = ns.character(at: pos)
                    if c != 0x0A { setSelectedRange(NSRange(location: pos + 1, length: 0)) }
                }
                needsDisplay = true; return true
            case "A":
                vimMode = .insert; moveToEndOfLine(nil); needsDisplay = true; return true
            case "o":
                moveToEndOfLine(nil)
                vimMode = .insert
                insertNewline(nil); needsDisplay = true; return true
            case "O":
                moveToBeginningOfLine(nil)
                vimMode = .insert
                insertNewline(nil)
                moveUp(nil); return true
            case "v":
                vimMode = .visual
                visualAnchor = selectedRange().location
                needsDisplay = true; return true
            case "h": moveLeft(nil);  return true
            case "j": moveDown(nil);  return true
            case "k": moveUp(nil);    return true
            case "l": moveRight(nil); return true
            case "w": moveWordForward(nil);  return true
            case "b": moveWordBackward(nil); return true
            case "0", "^": moveToBeginningOfLine(nil); return true
            case "$":       moveToEndOfLine(nil);       return true
            case "G":
                setSelectedRange(NSRange(location: string.utf16.count, length: 0)); return true
            case "x":
                // Delete char under cursor
                let pos = selectedRange().location
                let ns  = string as NSString
                if pos < ns.length, ns.character(at: pos) != 0x0A {
                    textStorage?.replaceCharacters(in: NSRange(location: pos, length: 1), with: "")
                    restyle(currentLine()); onTextChange?(string)
                }
                return true
            case "u":
                undoManager?.undo(); return true
            default:
                return false
            }

        case .visual:
            let noCtrl = !mods.contains(.control) && !mods.contains(.command) && !mods.contains(.option)
            guard noCtrl, chars.count == 1 else { return false }
            let ch = chars

            func extendSelection() {
                let cur = selectedRange().location + selectedRange().length
                let lo  = min(visualAnchor, cur)
                let hi  = max(visualAnchor, cur)
                setSelectedRange(NSRange(location: lo, length: hi - lo))
            }

            switch ch {
            case "h": moveLeft(nil);  extendSelection(); return true
            case "j": moveDown(nil);  extendSelection(); return true
            case "k": moveUp(nil);    extendSelection(); return true
            case "l": moveRight(nil); extendSelection(); return true
            case "w": moveWordForward(nil);  extendSelection(); return true
            case "b": moveWordBackward(nil); extendSelection(); return true
            case "d", "x":
                // Delete selection
                let sel = selectedRange()
                textStorage?.replaceCharacters(in: sel, with: "")
                restyle(currentLine()); onTextChange?(string)
                vimMode = .normal; needsDisplay = true; return true
            case "y":
                // Yank selection to pasteboard
                let sel  = selectedRange()
                let text = (string as NSString).substring(with: sel)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                setSelectedRange(NSRange(location: sel.location, length: 0))
                vimMode = .normal; needsDisplay = true; return true
            case "c":
                // Change: delete selection + enter insert mode
                let sel = selectedRange()
                textStorage?.replaceCharacters(in: sel, with: "")
                restyle(currentLine()); onTextChange?(string)
                vimMode = .insert; needsDisplay = true; return true
            default:
                return false
            }
        }
    }

    private func deleteCurrentLine() {
        guard let ts = textStorage else { return }
        let ns    = string as NSString
        let pos   = selectedRange().location
        // Find start of line
        var start = pos
        while start > 0 && ns.character(at: start - 1) != 0x0A { start -= 1 }
        // Find end of line (include newline)
        var end = pos
        while end < ns.length && ns.character(at: end) != 0x0A { end += 1 }
        if end < ns.length { end += 1 }  // consume the \n
        ts.replaceCharacters(in: NSRange(location: start, length: end - start), with: "")
        setSelectedRange(NSRange(location: min(start, ts.length), length: 0))
        restyle(currentLine()); onTextChange?(string)
    }

    // MARK: - Block cursor (Normal mode)

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn: Bool) {
        let vimEnabled = UserDefaults.standard.bool(forKey: "vimMode")
        guard vimEnabled, vimMode == .normal else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: turnedOn)
            return
        }
        guard turnedOn else { return }

        // Draw a block covering the character under the cursor
        guard let layout = layoutManager, let container = textContainer else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: turnedOn); return
        }
        let pos   = selectedRange().location
        let ns    = string as NSString
        let safePos = min(pos, max(0, ns.length - 1))
        let gRange  = layout.glyphRange(forCharacterRange: NSRange(location: safePos, length: max(1, 0)),
                                        actualCharacterRange: nil)
        var glRect  = layout.boundingRect(forGlyphRange: gRange, in: container)
        glRect.origin.x += textContainerInset.width
        glRect.origin.y += textContainerInset.height
        glRect.size.width = max(glRect.size.width, 9)

        color.withAlphaComponent(0.6).setFill()
        glRect.fill()
    }

    // MARK: - Mouse: tag clicks + table overlay tap-through

    override func mouseDown(with event: NSEvent) {
        dismissContactPopover()
        let pt = convert(event.locationInWindow, from: nil)

        if let layout = layoutManager, let container = textContainer, let ts = textStorage {
            let inset    = textContainerInset
            let adjusted = NSPoint(x: pt.x - inset.width, y: pt.y - inset.height)
            let idx      = layout.characterIndex(for: adjusted, in: container,
                                                 fractionOfDistanceBetweenInsertionPoints: nil)
            if idx < ts.length,
               let url = ts.attribute(.link, at: idx, effectiveRange: nil) as? URL {
                if url.scheme == "mdma" {
                    let host = url.host ?? ""
                    if host == "tag" {
                        NotificationCenter.default.post(name: .filterTag,
                                                        object: url.lastPathComponent)
                    } else if host == "anchor" {
                        let anchor = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                        scrollToAnchor(anchor)
                    } else if host == "contact" {
                        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                        if let c = ContactsManager.shared.find(name) {
                            NSWorkspace.shared.open(URL(string: "addressbook://\(c.identifier)")!)
                        }
                    } else if host == "ref" {
                        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                        FileSystemManager.shared.openFileRef(name)
                    } else if host == "note" {
                        // [wiki link] — resolve by stem name and open the file
                        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                        let fsm  = FileSystemManager.shared
                        let stem = name.lowercased()
                        if let found = fsm.allNoteURLs.first(where: {
                            $0.deletingPathExtension().lastPathComponent.lowercased() == stem
                        }) {
                            NotificationCenter.default.post(name: .openFile, object: found)
                        }
                    } else if host.isEmpty {
                        handleCrossFileLink(url)
                    }
                    return
                } else if url.scheme == "https" || url.scheme == "http" {
                    NSWorkspace.shared.open(url)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Anchor scroll

    private func scrollToAnchor(_ anchor: String) {
        func normalize(_ s: String) -> String {
            s.lowercased()
             .replacingOccurrences(of: " ", with: "-")
             .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
             .joined()
        }
        let target = normalize(anchor)
        let lines  = string.components(separatedBy: "\n")
        var offset = 0
        var found: Int?

        for line in lines {
            if let m = try? NSRegularExpression(pattern: #"^#{1,6}\s+(.+)"#)
                .firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let headingText = (line as NSString).substring(with: m.range(at: 1))
                let n = normalize(headingText)
                if n == target || n.hasSuffix(target) || n.contains(target) { found = offset; break }
            }
            offset += (line as NSString).length + 1
        }

        guard let loc = found,
              let layout = layoutManager, let container = textContainer else { return }
        setSelectedRange(NSRange(location: loc, length: 0))
        let gr   = layout.glyphRange(forCharacterRange: NSRange(location: loc, length: 0),
                                     actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: gr, in: container)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        rect.origin.y -= (enclosingScrollView?.contentView.bounds.height ?? 200) / 3
        enclosingScrollView?.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: max(0, rect.origin.y)))
    }

    // MARK: - Cross-file links

    private func handleCrossFileLink(_ url: URL) {
        guard let root = FileSystemManager.shared.rootURL else { return }
        var raw = url.path
        if raw.hasPrefix("/") { raw = String(raw.dropFirst()) }
        var filePath = raw
        var line: Int?
        if let m = try? NSRegularExpression(pattern: #"^(.+?):(\d+)(?::(\d+))?$"#)
            .firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
            filePath = (raw as NSString).substring(with: m.range(at: 1))
            line     = Int((raw as NSString).substring(with: m.range(at: 2)))
        }
        var fileURL = root.appendingPathComponent(filePath)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = fileURL.appendingPathExtension("md")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        NotificationCenter.default.post(name: .openFile, object: fileURL,
                                        userInfo: ["line": line as Any])
    }

    // MARK: - Scroll to line

    @objc private func handleScrollToLine(_ note: Notification) {
        guard let line = note.userInfo?["line"] as? Int, line > 0 else { return }
        let matchRange = note.userInfo?["matchRange"] as? NSRange
        let lines  = string.components(separatedBy: "\n")
        var offset = 0
        for (i, l) in lines.enumerated() {
            if i == line - 1 {
                if let mr = matchRange {
                    let abs  = NSRange(location: offset + mr.location, length: mr.length)
                    let safe = NSRange(location: min(abs.location, string.utf16.count),
                                       length:   min(abs.length, max(0, string.utf16.count - abs.location)))
                    setSelectedRange(safe)
                } else {
                    setSelectedRange(NSRange(location: offset, length: 0))
                }
                if let layout = layoutManager, let container = textContainer {
                    let gr   = layout.glyphRange(forCharacterRange: NSRange(location: offset, length: 0),
                                                 actualCharacterRange: nil)
                    var rect = layout.boundingRect(forGlyphRange: gr, in: container)
                    rect.origin.x += textContainerInset.width
                    rect.origin.y += textContainerInset.height
                    rect.origin.y -= (enclosingScrollView?.contentView.bounds.height ?? 200) / 3
                    enclosingScrollView?.contentView.animator().setBoundsOrigin(
                        NSPoint(x: 0, y: max(0, rect.origin.y)))
                }
                return
            }
            offset += (l as NSString).length + 1
        }
    }

}

// MARK: - String helper

private extension String {
    init?(utf16CodeUnit: UInt16) {
        guard let scalar = UnicodeScalar(utf16CodeUnit) else { return nil }
        self = String(scalar)
    }
}
