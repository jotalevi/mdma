import AppKit

// MARK: - File Link Picker Panel (non-activating, never steals focus)

class FileLinkPickerPanel: NSPanel {
    var onSelect:  ((String) -> Void)?   // passes the file stem (no .md extension)
    var onDismiss: (() -> Void)?

    private struct FileEntry {
        let stem:     String   // filename without .md — what gets inserted
        let subtitle: String   // relative parent folder path for disambiguation
    }

    private var entries:      [FileEntry] = []
    private var selectedIndex = 0
    private var rows:         [FileLinkRow] = []
    private let stack         = NSStackView()
    private let scroll        = NSScrollView()
    private let empty         = NSTextField(labelWithString: "No notes found")
    private weak var containerView: NSView?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 300),
            styleMask:   [.nonactivatingPanel, .borderless],
            backing:     .buffered,
            defer:       false
        )
        isFloatingPanel = true
        isOpaque        = false
        backgroundColor = .clear
        hasShadow       = true
        setupUI()

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange),
            name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Theme

    @objc private func handleThemeChange() {
        refreshColors()
        rebuildRows()
    }

    private func refreshColors() {
        guard let cv = containerView else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cv.layer?.backgroundColor = MarkdownParser.sidebar.withAlphaComponent(0.97).cgColor
        }
        empty.textColor = MarkdownParser.muted
    }

    // MARK: - Setup

    private func setupUI() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: 300))
        container.wantsLayer           = true
        container.layer?.cornerRadius  = 10
        container.layer?.masksToBounds = true
        containerView = container

        effectiveAppearance.performAsCurrentDrawingAppearance {
            container.layer?.backgroundColor = MarkdownParser.sidebar.withAlphaComponent(0.97).cgColor
        }

        empty.font      = .systemFont(ofSize: 12)
        empty.textColor = MarkdownParser.muted
        empty.alignment = .center
        empty.frame     = NSRect(x: 0, y: 115, width: 270, height: 20)
        empty.isHidden  = true
        container.addSubview(empty)

        stack.orientation  = .vertical
        stack.spacing      = 0
        stack.alignment    = .leading
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        let clip = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: 300))
        clip.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clip.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor)
        ])

        scroll.documentView        = clip
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers  = true
        scroll.drawsBackground     = false
        scroll.frame               = container.bounds
        scroll.autoresizingMask    = [.width, .height]
        container.addSubview(scroll)

        contentView = container
    }

    // MARK: - Update

    /// Filter the vault file list client-side as the user types.
    func update(allFiles: [URL], query: String, rootURL: URL?) {
        let q = query.lowercased()
        let filtered: [URL] = q.isEmpty
            ? allFiles
            : allFiles.filter { $0.deletingPathExtension().lastPathComponent.lowercased().contains(q) }

        entries = Array(filtered.prefix(8)).map { url in
            FileEntry(stem: url.deletingPathExtension().lastPathComponent,
                      subtitle: relativeFolderPath(url, root: rootURL))
        }
        selectedIndex = 0
        rebuildRows()
    }

    /// Returns the folder path relative to root, or "" if directly in root.
    private func relativeFolderPath(_ url: URL, root: URL?) -> String {
        guard let root = root else { return "" }
        let folderPath = url.deletingLastPathComponent().path
        let rootPath   = root.path
        guard folderPath != rootPath else { return "" }
        return String(folderPath.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
    }

    private func rebuildRows() {
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        empty.isHidden = !entries.isEmpty

        for (i, entry) in entries.enumerated() {
            let row = FileLinkRow(stem: entry.stem,
                                  subtitle: entry.subtitle,
                                  isSelected: i == selectedIndex,
                                  index: i,
                                  appearance: effectiveAppearance)
            row.onTap = { [weak self] idx in
                self?.selectedIndex = idx
                self?.selectCurrent()
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 270).isActive = true
            row.heightAnchor.constraint(equalToConstant: 46).isActive = true
            stack.addArrangedSubview(row)
            rows.append(row)
        }

        let h = entries.isEmpty ? CGFloat(50) : min(CGFloat(entries.count) * 46 + 8, 300)
        setContentSize(NSSize(width: 270, height: h))
        contentView?.frame = NSRect(x: 0, y: 0, width: 270, height: h)
        scroll.frame       = contentView?.bounds ?? .zero
    }

    // MARK: - Navigation

    private func highlight() {
        for (i, row) in rows.enumerated() { row.setSelected(i == selectedIndex) }
    }

    func moveDown() {
        guard !entries.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, entries.count - 1)
        highlight()
    }

    func moveUp() {
        guard !entries.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
        highlight()
    }

    func selectCurrent() {
        guard selectedIndex < entries.count else { return }
        onSelect?(entries[selectedIndex].stem)
    }
}

// MARK: - File Link Row

class FileLinkRow: NSView {
    var onTap: ((Int) -> Void)?
    private let index: Int
    private weak var nameLabel:     NSTextField?
    private weak var subtitleLabel: NSTextField?

    init(stem: String, subtitle: String, isSelected: Bool, index: Int, appearance: NSAppearance) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        setup(stem: stem, subtitle: subtitle, isSelected: isSelected, appearance: appearance)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { onTap?(index) }

    func setSelected(_ selected: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = selected
                ? MarkdownParser.accent.withAlphaComponent(0.2).cgColor
                : NSColor.clear.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            nameLabel?.textColor     = MarkdownParser.heading
            subtitleLabel?.textColor = MarkdownParser.muted
        }
    }

    private func setup(stem: String, subtitle: String, isSelected: Bool, appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = isSelected
                ? MarkdownParser.accent.withAlphaComponent(0.2).cgColor
                : NSColor.clear.cgColor
        }

        // Note icon (small square marker styled in accent colour)
        let icon = NSTextField(labelWithString: "◻")
        icon.font      = .systemFont(ofSize: 14)
        icon.textColor = MarkdownParser.accent
        icon.frame     = NSRect(x: 12, y: subtitle.isEmpty ? 14 : 18, width: 20, height: 20)
        addSubview(icon)

        // Note name
        let nl = NSTextField(labelWithString: stem)
        nl.font      = .systemFont(ofSize: 13, weight: .medium)
        nl.textColor = MarkdownParser.heading
        nl.frame     = subtitle.isEmpty
            ? NSRect(x: 38, y: 14, width: 222, height: 18)
            : NSRect(x: 38, y: 24, width: 222, height: 17)
        addSubview(nl)
        nameLabel = nl

        // Subtitle — relative folder path
        if !subtitle.isEmpty {
            let sl = NSTextField(labelWithString: subtitle)
            sl.font      = .systemFont(ofSize: 10)
            sl.textColor = MarkdownParser.muted
            sl.frame     = NSRect(x: 38, y: 9, width: 222, height: 13)
            addSubview(sl)
            subtitleLabel = sl
        }
    }
}
