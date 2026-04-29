import AppKit
import Foundation
import Combine

// MARK: - Reference model

struct SearchHit: Identifiable {
    let id = UUID()
    let url: URL
    let line: Int
    let lineText: String
    let matchRange: NSRange
}

struct Reference: Identifiable, Hashable {
    enum Kind: Hashable {
        case tag(String)
        case contact(String)
        case fileRef(String, URL?)   // display name, resolved URL in .mdma_refs
        case link(URL)
    }
    var id: String { "\(kind)-\(sourceNote.lastPathComponent)" }
    var kind: Kind
    var sourceNote: URL
    var display: String
    static func == (l: Reference, r: Reference) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

class FileSystemManager: ObservableObject {
    static let shared = FileSystemManager()

    @Published var rootURL:        URL?
    @Published var tree:           [FileItem]   = []
    @Published var allTags:        [String]     = []
    @Published var references:     [Reference]  = []
    @Published var archiveItems:   [FileItem]   = []
    @Published var templateItems:  [FileItem]   = []
    @Published var backlinkIndex:  [URL: [URL]] = [:]   // note URL → [URLs that link to it]

    /// All markdown files in the vault tree (for the file-link picker).
    var allNoteURLs: [URL] { flatFiles(tree) }
    /// Reactive store for pinned paths — drives SidebarView re-renders
    @Published var pinnedPaths:    [String]     = {
        UserDefaults.standard.stringArray(forKey: "pinnedPaths") ?? []
    }()

    private var watchSource: DispatchSourceFileSystemObject?
    private var deletedURLs = Set<URL>()
    private static let contactRx  = try! NSRegularExpression(pattern: #"@(\S[^@\n]*\S|\S)@"#)
    private static let fileRefRx  = try! NSRegularExpression(pattern: #"\|(\S[^|\n]*\S|\S)\|"#)
    private static let wikiLinkRx = try! NSRegularExpression(pattern: #"(?<!!)(?<!\[)\[([^\[\]\n]+)\](?!\()(?!\[)"#)
    private static let linkRx     = try! NSRegularExpression(pattern: #"https?://[^\s\)]+"#)

    var refsFolder: URL? {
        rootURL?.appendingPathComponent(".mdma_refs")
    }

    init() {
        let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let lastBuild    = UserDefaults.standard.string(forKey: "lastLaunchedBuild")

        // First ever launch on this machine — wipe any stale state
        if lastBuild == nil {
            UserDefaults.standard.removeObject(forKey: "rootBookmark")
        }

        UserDefaults.standard.set(buildVersion, forKey: "lastLaunchedBuild")
        restoreRoot()
    }
    // MARK: - Root

    func pickRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.prompt = "Choose Root Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setRoot(url)
    }

    func setRoot(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        if let bm = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(bm, forKey: "rootBookmark")
        }
        rootURL = url
        ensureRefsFolder()
        refresh()
        watch(url)
        GitManager.shared.configure(rootURL: url)
    }

    func clearRoot() {
        watchSource?.cancel()
        rootURL = nil; tree = []; allTags = []; references = []
        UserDefaults.standard.removeObject(forKey: "rootBookmark")
    }
    
    func search(_ query: String) -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for url in flatFiles(tree) {
            guard let content = rawContent(url) else { continue }
            let lines = content.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let ns = line as NSString
                let range = ns.range(of: query, options: .caseInsensitive)
                if range.location != NSNotFound {
                    let snippet = line.trimmingCharacters(in: .whitespaces)
                    hits.append(SearchHit(url: url, line: i + 1,
                                          lineText: snippet, matchRange: range))
                }
            }
        }
        return hits
    }


    private func restoreRoot() {
        guard let data = UserDefaults.standard.data(forKey: "rootBookmark") else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(fresh, forKey: "rootBookmark")
        }
        rootURL = url
        ensureRefsFolder()
        refresh()
        watch(url)
    }

    private func ensureRefsFolder() {
        guard let refs = refsFolder else { return }
        if !FileManager.default.fileExists(atPath: refs.path) {
            try? FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard let root = rootURL else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let newTree   = self.buildTree(at: root)
            let tags      = Array(self.gatherTags(newTree)).sorted()
            let refs      = self.gatherReferences(newTree)
            let archive   = self.mdFiles(in: root.appendingPathComponent("_archive"))
            let templates = self.mdFiles(in: root.appendingPathComponent("_templates"))
            let backlinks = self.buildBacklinkIndex(newTree)
            DispatchQueue.main.async {
                self.tree          = newTree
                self.allTags       = tags
                self.references    = refs
                self.archiveItems  = archive
                self.templateItems = templates
                self.backlinkIndex = backlinks
            }
        }
    }

    // MARK: - Backlink Index

    /// Builds a reverse map: note URL → [URLs of notes that contain a link pointing to it].
    /// Recognises both |pipe-ref| and [note-link] syntaxes.
    private func buildBacklinkIndex(_ items: [FileItem]) -> [URL: [URL]] {
        let allFiles = flatFiles(items)
        // Stem → URL lookup (case-insensitive)
        var nameToURL: [String: URL] = [:]
        for url in allFiles {
            let stem = url.deletingPathExtension().lastPathComponent.lowercased()
            let full = url.lastPathComponent.lowercased()
            nameToURL[stem] = url
            nameToURL[full] = url
        }

        var index: [URL: [URL]] = [:]
        for source in allFiles {
            guard let raw = rawContent(source) else { continue }
            let text = stripCode(raw)
            let ns   = text as NSString
            let len  = ns.length
            var targets = Set<URL>()

            // |pipe refs|
            Self.fileRefRx.matches(in: text, range: NSRange(location: 0, length: len)).forEach { m in
                if let r = Range(m.range(at: 1), in: text) {
                    let key = String(text[r]).lowercased()
                    let stem = (key as NSString).deletingPathExtension.lowercased()
                    if let t = nameToURL[key] ?? nameToURL[stem], t != source { targets.insert(t) }
                }
            }

            // [note links] — new single-bracket syntax
            Self.wikiLinkRx.matches(in: text, range: NSRange(location: 0, length: len)).forEach { m in
                if let r = Range(m.range(at: 1), in: text) {
                    let raw  = String(text[r]).trimmingCharacters(in: .whitespaces).lowercased()
                    let stem = (raw as NSString).deletingPathExtension.lowercased()
                    if let t = nameToURL[raw] ?? nameToURL[stem] ?? nameToURL[stem + ".md"],
                       t != source { targets.insert(t) }
                }
            }

            for t in targets { index[t, default: []].append(source) }
        }
        return index
    }

    private func mdFiles(in folder: URL) -> [FileItem] {
        guard FileManager.default.fileExists(atPath: folder.path),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else { return [] }
        return entries
            .filter { $0.pathExtension == "md" }
            .map    { FileItem(url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private let specialFolders: Set<String> = [".DS_Store", ".mdma_refs", "_archive", "_templates"]

    private func buildTree(at url: URL) -> [FileItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return [] }
        return entries
            .filter { u in
                let name = u.lastPathComponent
                // Only exclude special folders at root level
                if u.deletingLastPathComponent().path == rootURL?.path {
                    return !specialFolders.contains(name)
                }
                return name != ".DS_Store"
            }
            .compactMap { u -> FileItem? in
                let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir { return FileItem(url: u, children: buildTree(at: u)) }
                if u.pathExtension == "md" { return FileItem(url: u) }
                return nil
            }
            .sorted {
                $0.isDirectory != $1.isDirectory
                    ? $0.isDirectory
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    // MARK: - Tags

    func parseTags(_ text: String) -> Set<String> {
        let stripped = stripCode(text)
        let ns = stripped as NSString
        var tags = Set<String>()
        (try? NSRegularExpression(pattern: #"\$(\S[^$\n]*\S|\S)\$"#))?
            .matches(in: stripped, range: NSRange(location: 0, length: ns.length)).forEach {
                if let r = Range($0.range(at: 1), in: stripped) {
                    tags.insert(String(stripped[r]).trimmingCharacters(in: .whitespaces).lowercased())
                }
            }
        return tags
    }

    private func stripCode(_ text: String) -> String {
        // Remove fenced code blocks
        var result = text
        if let rx = try? NSRegularExpression(pattern: #"```[\s\S]*?```"#) {
            result = rx.stringByReplacingMatches(
                in: result, range: NSRange(location: 0, length: (result as NSString).length),
                withTemplate: "")
        }
        // Remove inline code
        if let rx = try? NSRegularExpression(pattern: #"`[^`\n]+`"#) {
            result = rx.stringByReplacingMatches(
                in: result, range: NSRange(location: 0, length: (result as NSString).length),
                withTemplate: "")
        }
        return result
    }
    private func gatherTags(_ items: [FileItem]) -> Set<String> {
        items.reduce(into: Set<String>()) { acc, item in
            if item.isDirectory { acc.formUnion(gatherTags(item.children ?? [])) }
            else if let t = rawContent(item.url) { acc.formUnion(parseTags(t)) }
        }
    }

    func files(withTag tag: String) -> [URL] {
        flatFiles(tree).filter { (rawContent($0).map { parseTags($0).contains(tag) }) ?? false }
    }

    private func flatFiles(_ items: [FileItem]) -> [URL] {
        items.flatMap { $0.isDirectory ? flatFiles($0.children ?? []) : [$0.url] }
    }

    // MARK: - References

    private func gatherReferences(_ items: [FileItem]) -> [Reference] {
        var result: [Reference] = []
        for url in flatFiles(items) {
            guard let raw = rawContent(url) else { continue }
            let text = stripCode(raw)   // ← strip code before scanning
            let ns  = text as NSString
            let len = ns.length

            // @contacts
            Self.contactRx.matches(in: text, range: NSRange(location: 0, length: len)).forEach { m in
                if let r = Range(m.range(at: 1), in: text) {
                    let name = String(text[r])
                    let ref  = Reference(kind: .contact(name), sourceNote: url, display: "@\(name)")
                    if !result.contains(ref) { result.append(ref) }
                }
            }

            // |file refs|
            Self.fileRefRx.matches(in: text, range: NSRange(location: 0, length: len)).forEach { m in
                if let r = Range(m.range(at: 1), in: text) {
                    let name     = String(text[r])
                    let resolved = refsFolder?.appendingPathComponent(name)
                    let ref      = Reference(kind: .fileRef(name, resolved), sourceNote: url, display: name)
                    if !result.contains(ref) { result.append(ref) }
                }
            }

            // Links
            Self.linkRx.matches(in: text, range: NSRange(location: 0, length: len)).forEach { m in
                if let r = Range(m.range, in: text), let url2 = URL(string: String(text[r])) {
                    let ref = Reference(kind: .link(url2), sourceNote: url, display: url2.host ?? url2.absoluteString)
                    if !result.contains(ref) { result.append(ref) }
                }
            }
        }
        return result
    }

    // MARK: - File References (|file|)

    /// Copy a file into .mdma_refs and return the filename for insertion as |name|
    @discardableResult
    func addFileReference(_ sourceURL: URL) -> String? {
        guard let refs = refsFolder else { return nil }
        ensureRefsFolder()
        let _ = sourceURL.lastPathComponent
        let dest = unique(in: refs, name: sourceURL.deletingPathExtension().lastPathComponent,
                         ext: sourceURL.pathExtension.isEmpty ? nil : sourceURL.pathExtension)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch { return nil }
        refresh()
        return dest.lastPathComponent
    }

    func openFileRef(_ name: String) {
        guard let refs = refsFolder else { return }
        let url = refs.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Watch

    private func watch(_ url: URL) {
        watchSource?.cancel()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .link],
            queue: .global(qos: .background)
        )
        src.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchSource = src
    }

    // MARK: - CRUD

    // MARK: - Pinned Notes

    var pinnedURLs: [URL] { pinnedPaths.map { URL(fileURLWithPath: $0) } }

    func isPinned(_ url: URL) -> Bool { pinnedPaths.contains(url.path) }

    func pin(_ url: URL) {
        guard !pinnedPaths.contains(url.path) else { return }
        pinnedPaths.append(url.path)
        UserDefaults.standard.set(pinnedPaths, forKey: "pinnedPaths")
    }

    func unpin(_ url: URL) {
        pinnedPaths.removeAll { $0 == url.path }
        UserDefaults.standard.set(pinnedPaths, forKey: "pinnedPaths")
    }

    // MARK: - Archive

    var archiveFolder: URL? { rootURL?.appendingPathComponent("_archive") }

    func archive(_ url: URL) {
        guard let dest = archiveFolder else { return }
        // Close any open tab first so the editor cannot re-save to the old path after the move.
        NotificationCenter.default.post(name: .closeTabForURL, object: url)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        }
        let target = dest.appendingPathComponent(url.lastPathComponent)
        // Brief delay lets the tab close flush any pending write before we move.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            try? FileManager.default.moveItem(at: url, to: target)
            self.unpin(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.refresh() }
        }
    }

    func unarchive(_ url: URL) {
        guard let root = rootURL else { return }
        NotificationCenter.default.post(name: .closeTabForURL, object: url)
        let target = root.appendingPathComponent(url.lastPathComponent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            try? FileManager.default.moveItem(at: url, to: target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.refresh() }
        }
    }

    // MARK: - Templates

    var templatesFolder: URL? { rootURL?.appendingPathComponent("_templates") }

    @discardableResult
    func createFromTemplate(_ template: URL, near sibling: URL? = nil) -> URL? {
        let folder = sibling.flatMap {
            let isDir = (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir ? $0 : $0.deletingLastPathComponent()
        } ?? rootURL ?? template.deletingLastPathComponent()
        let name = template.deletingPathExtension().lastPathComponent
        let dest = unique(in: folder, name: name, ext: "md")
        let content = (try? String(contentsOf: template, encoding: .utf8)) ?? ""
        try? content.write(to: dest, atomically: true, encoding: .utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.refresh() }
        return dest
    }

    @discardableResult
    func saveAsTemplate(name: String, content: String) -> URL? {
        guard let folder = templatesFolder else { return nil }
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let dest = unique(in: folder, name: name, ext: "md")
        try? content.write(to: dest, atomically: true, encoding: .utf8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.refresh() }
        return dest
    }

    // MARK: - Daily Notes

    @discardableResult
    func openOrCreateDailyNote() -> URL? {
        guard let root = rootURL else { return nil }
        let dailyFolder = root.appendingPathComponent("Daily")
        if !FileManager.default.fileExists(atPath: dailyFolder.path) {
            try? FileManager.default.createDirectory(at: dailyFolder, withIntermediateDirectories: true)
        }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let name = fmt.string(from: Date())
        let dest = dailyFolder.appendingPathComponent("\(name).md")
        if !FileManager.default.fileExists(atPath: dest.path) {
            let header = "# \(name)\n\n"
            try? header.write(to: dest, atomically: true, encoding: .utf8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.refresh() }
        return dest
    }

    // MARK: - CRUD

    func rawContent(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func save(_ content: String, to url: URL) {
        guard !deletedURLs.contains(url) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self?.deletedURLs.contains(url) == false else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    func createFile(in folder: URL, name: String = "Untitled") -> URL? {
        let url = unique(in: folder, name: name, ext: "md")
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else { return nil }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let root = self.rootURL else { return }
            let t = self.buildTree(at: root)
            DispatchQueue.main.async { self.tree = t }
        }
        return url
    }

    @discardableResult
    func createFolder(in parent: URL, name: String = "New Folder") -> URL? {
        let url = unique(in: parent, name: name, ext: nil)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        catch { return nil }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let root = self.rootURL else { return }
            let t = self.buildTree(at: root)
            DispatchQueue.main.async { self.tree = t }
        }
        return url
    }

    func delete(_ url: URL) {
        deletedURLs.insert(url)
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        refresh()
    }

    @discardableResult
    func rename(_ url: URL, to newName: String) -> URL? {
        let ext = url.pathExtension
        var dst = url.deletingLastPathComponent().appendingPathComponent(newName)
        if !ext.isEmpty { dst = dst.appendingPathExtension(ext) }
        guard (try? FileManager.default.moveItem(at: url, to: dst)) != nil else { return nil }
        deletedURLs.insert(url)
        refresh(); return dst
    }

    @discardableResult
    func move(_ url: URL, to destFolder: URL) -> URL? {
        let dst = unique(in: destFolder,
                         name: url.deletingPathExtension().lastPathComponent,
                         ext: url.pathExtension.isEmpty ? nil : url.pathExtension)
        guard (try? FileManager.default.moveItem(at: url, to: dst)) != nil else { return nil }
        deletedURLs.insert(url)
        refresh()
        return dst
    }

    func copyFile(_ url: URL, to destFolder: URL) {
        let dst = unique(in: destFolder,
                         name: url.deletingPathExtension().lastPathComponent,
                         ext: url.pathExtension.isEmpty ? nil : url.pathExtension)
        try? FileManager.default.copyItem(at: url, to: dst)
        refresh()
    }

    func createWelcomeFileIfNeeded() {
        guard let root = rootURL else { return }
        let welcomeURL = root.appendingPathComponent("Welcome.md")
        guard !FileManager.default.fileExists(atPath: welcomeURL.path) else { return }

        // ── 1. Welcome.md ───────────────────────────────────────────────
        let welcome = """
# Welcome to mdma 👋

mdma is a minimal, keyboard-first markdown editor for Mac. Notes live as plain `.md` files — open them anywhere, sync with iCloud, own them forever.

> **You're looking at the onboarding suite.** Four notes linked and backlinked to each other. Explore them to discover everything mdma can do, then delete them when you're ready.

## Your vault at a glance

| Note | What's inside |
| --- | --- |
| [Getting Started] | Writing, syntax, and mdma's special markers |
| [Power Features] | Shortcuts, graph view, backlinks, git |
| [My First Note] | A blank canvas ready for your first real thought |

You can also jump there with a file reference: |Getting Started.md|

## The editor in one sentence

The line your **cursor** is on shows raw Markdown syntax. Move away and it renders. Come back and syntax reappears. No modes, no toggles — just type.

## mdma's four special markers

- **$Tags$** — wrap text in `$dollar signs$` to tag a note. Click tags in the sidebar to filter.
- **@Contacts@** — wrap a name in `@at signs@` to mention someone. Click to open them in Contacts.
- **|File refs|** — wrap a filename in `|pipes|` to attach a file. Press `⌘⇧A` to pick one from Finder.
- **[Wiki links]** — wrap a note name in `[single brackets]` to link notes together. Type `[` to open the note picker.

This note is tagged $mdma$ and $onboarding$. It was set up by @mdma bot@.

## Navigation

| Action | Shortcut |
| --- | --- |
| Quick Switcher | ⌘P |
| Focus sidebar search | ⌘⇧F |
| Toggle Outline panel | ⌘L |

---

*Start with [Getting Started] →, or jump straight to [Power Features] if you're feeling bold.*

> *Delete this file whenever you're ready. Happy writing.*
"""

        // ── 2. Getting Started.md ────────────────────────────────────────
        let gettingStarted = """
# Getting Started

← Back to [Welcome]

This note walks through Markdown basics and mdma's four special markers. Toggle the Outline panel (`⌘L`) to jump between sections.

---

## Markdown basics

### Headings

Use `#` for H1, `##` for H2, `###` for H3 and so on. Every heading appears in the Outline panel on the right — open it now with `⌘L`.

### Emphasis

**Bold**, *italic*, ***bold italic***, ~~strikethrough~~.

### Lists & tasks

- Unordered list item
  - Nested item (two spaces)

1. Ordered list
2. Second item

- [ ] Pending task
- [x] Completed task

### Blockquotes

> Use `>` at the start of a line for a blockquote. Great for callouts, warnings, or anything worth highlighting.

### Code

Inline `code` with backticks. Triple backticks for fenced blocks:

```swift
func greet(_ name: String) -> String {
    return "Hello, \\(name)!"
}
```

### Tables

Put the separator row after the header:

| Feature | Shortcut |
| --- | --- |
| New note | ⌘N |
| Find | ⌘F |
| Find & Replace | ⌘H |
| Quick Switcher | ⌘P |
| Outline toggle | ⌘L |

Or start with the separator for a headless table:

| --- | --- |
| plain | no header |
| still useful | for grids |

### Links

Standard: [anthropic.com](https://anthropic.com)
Anchor (same file): [Back to top](#getting-started)
Cross-file: [Power Features](mdma:///Power Features)

---

## mdma extensions

### $Tags$

Wrap text in `$dollar signs$` — no spaces next to the delimiters.

This note is tagged $getting-started$ and $markdown$.

Tags appear in the **TAGS** section of the sidebar. Click any tag to filter the file list.

### @Contact mentions@

Wrap a name in `@at signs@` — no spaces next to the delimiters.

Reviewed by @Jane Doe@.

Type `@` after a space to trigger the contact autocomplete popover. `↑↓` to navigate, `Enter` to insert, `Esc` to dismiss. Click a rendered mention to open them in macOS Contacts.

### |File references|

Wrap a filename in `|pipes|` — no spaces next to the delimiters.

See attached: |project-brief.pdf|

Press `⌘⇧A` to pick any file from your Mac. It's copied into a hidden `.mdma_refs` folder and linked automatically. Click the reference in the **References** sidebar to open it.

> **Tip:** `| text |` with spaces is a table cell. Only `|filename|` with no spaces is a file reference. Same applies to `$tag$` and `@Contact@`.

### [Wiki links]

Wrap a note name in `[single brackets]` to link to another note. Type `[` to open the note picker — `↑↓` to navigate, `Enter` to insert, `Esc` to dismiss.

See [Power Features] for shortcuts, graph, and git. Return to [Welcome] any time.

Backlinks are tracked automatically. Open [Power Features] and look at the **LINKED BY** section at the bottom of the sidebar — this note will appear there.

---

## Auto-closing pairs

mdma closes `()`, `[]`, `{}`, `<>`, `$$`, `@@`, and `||` automatically. With text selected, typing an opener **wraps the selection**. Try selecting a word and pressing `$`.

---

*Continue to [Power Features] →*
"""

        // ── 3. Power Features.md ─────────────────────────────────────────
        let powerFeatures = """
# Power Features

← [Getting Started] · [Welcome]

All of mdma's advanced capabilities, one section each. Try them as you read.

---

## Outline panel `⌘L`

Toggle the right-side Outline panel with `⌘L`. It lists every heading in the current note as a clickable row. Instant in-document navigation without scrolling.

---

## Find & Replace

- `⌘F` — open the **Find** bar
- `⌘H` — open **Find & Replace**

Type to search — matches highlight yellow, current match highlights orange. `↑↓` or the arrow buttons step through. Toggle **Aa** for case-sensitive search. Replace one match or all. `Esc` closes the bar and clears all highlights.

---

## Quick Switcher `⌘P`

Press `⌘P`, type any part of a note name, press `Enter`. Fastest way to jump between notes without touching the sidebar.

---

## Sidebar search `⌘⇧F`

Press `⌘⇧F` to focus the sidebar search. Searches filenames and file contents simultaneously. Results show filename, line number, and a match snippet. Click to open the file and jump the cursor to that line.

---

## Backlinks

When another note links to this one using `[Power Features]` or `|Power Features.md|`, it appears in the **LINKED BY** section at the bottom of the sidebar.

Right now [Getting Started] and [Welcome] both link here — check the sidebar.

---

## Graph view

Click the **⬡ graph button** in the top bar to open the Graph View. Every note is a node; every link is an edge. Nodes are sized by connection count — highly linked notes are bigger.

- **Drag** nodes to reposition
- **Click** a node to open that note
- **Re-layout** reruns the force simulation

The four onboarding notes ($mdma$, $onboarding$, $getting-started$) will cluster together because they link densely.

---

## Pinning

Right-click any file → **Pin**. Pinned files appear in a **PINNED** section at the top of the sidebar *and* stay visible in the normal file browser with a pin indicator. Unpin the same way.

---

## Archiving

Right-click a file → **Archive**. Moves the file into a hidden `.mdma_archive` folder — out of the way, never deleted. Right-click again to **Unarchive** and move it back.

---

## Themes

Open **Preferences** (`⌘,`) → Appearance:

| Theme | Flavour |
| --- | --- |
| Original | Dark slate — the default |
| High Contrast | Stark black & white |
| Pastel | Soft muted colours |
| Solarized | Ethan Schoonover's classic |
| Nord | Arctic blue |
| Sepia | Warm parchment |

All six themes adapt to macOS dark/light mode automatically.

---

## Vim mode

Enable **Vim mode** in Preferences. Adds normal / insert / visual modes with standard Vim keybindings. The current mode is shown in the status bar at the bottom of the editor.

---

## Git integration

If your root folder is a git repository, mdma shows:

- **Coloured dots** next to files — orange for modified, teal for untracked
- A **branch button** in the top bar with the current branch and uncommitted-change count
- A **Commit sheet** (click the branch button) to write a message and commit all changes
- An **Auto-commit on save** toggle in Preferences → Git

---

## iCloud sync

Move your root folder into **iCloud Drive** and macOS syncs everything automatically. Change the root via **mdma menu → Change Root Folder**.

---

*You're all set. Go back to [Welcome], or open [My First Note] and start writing.*
"""

        // ── 4. My First Note.md ──────────────────────────────────────────
        let myFirstNote = """
# My First Note

The onboarding suite ([Welcome], [Getting Started], [Power Features]) is always a `⌘P` away.

$idea$ $draft$

---

Write something here.
"""

        let files: [(String, String)] = [
            ("Welcome.md",          welcome),
            ("Getting Started.md",  gettingStarted),
            ("Power Features.md",   powerFeatures),
            ("My First Note.md",    myFirstNote)
        ]

        for (name, body) in files {
            let fileURL = root.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            try? body.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        refresh()
    }

    private func unique(in dir: URL, name: String, ext: String?) -> URL {
        func make(_ s: String) -> URL {
            let u = dir.appendingPathComponent(s)
            return ext.map { u.appendingPathExtension($0) } ?? u
        }
        var url = make(name); var i = 2
        while FileManager.default.fileExists(atPath: url.path) { url = make("\(name) \(i)"); i += 1 }
        return url
    }
}

extension Notification.Name {
    static let newNote          = Notification.Name("mdma.newNote")
    static let newFolder        = Notification.Name("mdma.newFolder")
    static let filterTag        = Notification.Name("mdma.filterTag")
    static let closeTab         = Notification.Name("mdma.closeTab")
    static let insertFileRef    = Notification.Name("mdma.insertFileRef")
    static let openFile         = Notification.Name("mdma.openFile")
    static let scrollToLine     = Notification.Name("mdma.scrollToLine")
    static let insertText       = Notification.Name("mdma.insertText")
    static let tearOffTab       = Notification.Name("mdma.tearOffTab")
    static let toggleFocus      = Notification.Name("mdma.toggleFocus")
    static let focusSidebar     = Notification.Name("mdma.focusSidebar")
    static let focusSearch      = Notification.Name("mdma.focusSearch")
    static let closeTabForURL   = Notification.Name("mdma.closeTabForURL")
    static let fileURLDidChange = Notification.Name("mdma.fileURLDidChange")
    static let themeDidChange        = Notification.Name("mdma.themeDidChange")
    static let vimModeSettingChanged = Notification.Name("mdma.vimModeSettingChanged")
    static let spellCheckChanged     = Notification.Name("mdma.spellCheckChanged")
}
