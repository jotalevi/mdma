import AppKit
import Contacts

// MARK: - Contact Picker Panel (non-activating, never steals focus)

class ContactPickerPanel: NSPanel {
    var onSelect:  ((CNContact) -> Void)?
    var onDismiss: (() -> Void)?

    private var contacts: [CNContact] = []
    private var selectedIndex = 0
    private var rows: [ContactRow] = []
    private let stack       = NSStackView()
    private let scroll      = NSScrollView()
    private let empty       = NSTextField(labelWithString: "No contacts found")
    private weak var containerView: NSView?   // kept for theme refresh

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
        // Rebuild rows so new ContactRow instances are created with fresh colors
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
        container.wantsLayer          = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        containerView = container

        // Set initial background via the theme system (appearance-aware)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            container.layer?.backgroundColor = MarkdownParser.sidebar.withAlphaComponent(0.97).cgColor
        }

        // Empty label
        empty.font      = .systemFont(ofSize: 12)
        empty.textColor = MarkdownParser.muted
        empty.alignment = .center
        empty.frame     = NSRect(x: 0, y: 130, width: 270, height: 20)
        empty.isHidden  = true
        container.addSubview(empty)

        // Stack in scroll
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

    func update(contacts: [CNContact]) {
        self.contacts      = contacts
        self.selectedIndex = 0
        rebuildRows()
    }

    private func rebuildRows() {
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        empty.isHidden = !contacts.isEmpty

        for (i, contact) in contacts.enumerated() {
            // Pass the panel's current effective appearance so the row resolves
            // layer cgColors correctly even before it enters the view hierarchy.
            let row = ContactRow(contact: contact,
                                 isSelected: i == selectedIndex,
                                 index: i,
                                 appearance: effectiveAppearance)
            row.onTap = { [weak self] idx in
                self?.selectedIndex = idx
                self?.selectCurrent()
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 270).isActive = true
            row.heightAnchor.constraint(equalToConstant: 52).isActive = true
            stack.addArrangedSubview(row)
            rows.append(row)
        }

        let h = min(CGFloat(contacts.count) * 52 + 8, 300)
        setContentSize(NSSize(width: 270, height: h))
        contentView?.frame = NSRect(x: 0, y: 0, width: 270, height: h)
        scroll.frame       = contentView?.bounds ?? .zero
    }

    // MARK: - Navigation

    private func highlight() {
        for (i, row) in rows.enumerated() { row.setSelected(i == selectedIndex) }
    }

    func moveDown() {
        guard !contacts.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, contacts.count - 1)
        highlight()
    }

    func moveUp() {
        guard !contacts.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
        highlight()
    }

    func selectCurrent() {
        guard selectedIndex < contacts.count else { return }
        onSelect?(contacts[selectedIndex])
    }
}

// MARK: - Contact Row

class ContactRow: NSView {
    var onTap: ((Int) -> Void)?
    private let index: Int

    // Stored refs for color refresh
    private weak var avatarView:  NSView?
    private weak var nameLabel:   NSTextField?
    private weak var subLabel:    NSTextField?
    private weak var initialLabel: NSTextField?

    init(contact: CNContact, isSelected: Bool, index: Int, appearance: NSAppearance) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        setup(contact: contact, isSelected: isSelected, appearance: appearance)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { onTap?(index) }

    // Called during keyboard navigation — row is live in the hierarchy here.
    func setSelected(_ selected: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = selected
                ? MarkdownParser.accent.withAlphaComponent(0.2).cgColor
                : NSColor.clear.cgColor
        }
    }

    // Re-apply all theme colors (called on theme/appearance change).
    func refreshColors(appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            self.avatarView?.layer?.backgroundColor  = MarkdownParser.accent.withAlphaComponent(0.25).cgColor
            self.initialLabel?.textColor             = MarkdownParser.accent
            self.nameLabel?.textColor                = MarkdownParser.heading
            self.subLabel?.textColor                 = MarkdownParser.muted
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors(appearance: effectiveAppearance)
    }

    private func setup(contact: CNContact, isSelected: Bool, appearance: NSAppearance) {
        // Resolve all CALayer colors inside the given appearance context.
        appearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = isSelected
                ? MarkdownParser.accent.withAlphaComponent(0.2).cgColor
                : NSColor.clear.cgColor
        }

        // Avatar circle
        let av = NSView(frame: NSRect(x: 12, y: 10, width: 32, height: 32))
        av.wantsLayer          = true
        av.layer?.cornerRadius = 16
        av.layer?.masksToBounds = true
        appearance.performAsCurrentDrawingAppearance {
            av.layer?.backgroundColor = MarkdownParser.accent.withAlphaComponent(0.25).cgColor
        }
        avatarView = av

        if let data = contact.thumbnailImageData, let img = NSImage(data: data) {
            let iv = NSImageView(frame: av.bounds)
            iv.image               = img
            iv.imageScaling        = .scaleProportionallyUpOrDown
            iv.wantsLayer          = true
            iv.layer?.cornerRadius = 16
            iv.layer?.masksToBounds = true
            av.addSubview(iv)
        } else {
            let initial = NSTextField(
                labelWithString: String(ContactsManager.shared.displayName(contact).prefix(1)).uppercased()
            )
            initial.font      = .boldSystemFont(ofSize: 14)
            initial.textColor = MarkdownParser.accent   // dynamic NSColor — adapts automatically
            initial.frame     = NSRect(x: 0, y: 8, width: 32, height: 18)
            initial.alignment = .center
            av.addSubview(initial)
            initialLabel = initial
        }
        addSubview(av)

        // Name
        let name = NSTextField(labelWithString: ContactsManager.shared.displayName(contact))
        name.font      = .systemFont(ofSize: 13, weight: .medium)
        name.textColor = MarkdownParser.heading   // dynamic NSColor — adapts automatically
        name.frame     = NSRect(x: 54, y: 22, width: 206, height: 17)
        addSubview(name)
        nameLabel = name

        // Subtitle
        let sub: String
        if let email = contact.emailAddresses.first {
            sub = String(email.value)
        } else if let phone = contact.phoneNumbers.first {
            sub = phone.value.stringValue
        } else {
            sub = ""
        }
        if !sub.isEmpty {
            let sl = NSTextField(labelWithString: sub)
            sl.font      = .systemFont(ofSize: 10)
            sl.textColor = MarkdownParser.muted   // dynamic NSColor — adapts automatically
            sl.frame     = NSRect(x: 54, y: 8, width: 206, height: 13)
            addSubview(sl)
            subLabel = sl
        }
    }
}
