import Foundation
import Combine
import UIKit

// MARK: - Models

struct SearchHit: Identifiable {
    let id  = UUID()
    let url: URL
    let line: Int
    let lineText: String
    let matchRange: NSRange
}

struct Reference: Identifiable, Hashable {
    enum Kind: Hashable {
        case tag(String)
        case contact(String)
        case fileRef(String, URL?)
        case link(URL)
    }
    var id: String { "\(kind)-\(sourceNote.lastPathComponent)" }
    var kind: Kind
    var sourceNote: URL
    var display: String
    static func == (l: Reference, r: Reference) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - FileSystemManager

class FileSystemManager: ObservableObject {
    static let shared = FileSystemManager()

    @Published var rootURL:    URL?
    @Published var tree:       [FileItem]  = []
    @Published var allTags:    [String]    = []
    @Published var references: [Reference] = []

    private var watchSource: DispatchSourceFileSystemObject?
    private var deletedURLs = Set<URL>()
    private static let contactRx = try! NSRegularExpression(pattern: #"@(\S[^@\n]*\S|\S)@"#)
    private static let fileRefRx = try! NSRegularExpression(pattern: #"\|(\S[^|\n]*\S|\S)\|"#)
    private static let linkRx    = try! NSRegularExpression(pattern: #"https?://[^\s\)]+"#)

    var refsFolder: URL? { rootURL?.appendingPathComponent(".mdma_refs") }

    // iOS: root is always Documents/mdma/
    static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mdma", isDirectory: true)
    }

    init() {
        let root = FileSystemManager.defaultRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        rootURL = root
        ensureRefsFolder()
        refresh()
        watch(root)
    }

    // MARK: - Search

    func search(_ query: String) -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for url in flatFiles(tree) {
            guard let content = rawContent(url) else { continue }
            let lines = content.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let ns    = line as NSString
                let range = ns.range(of: query, options: .caseInsensitive)
                if range.location != NSNotFound {
                    hits.append(SearchHit(url: url, line: i + 1,
                                          lineText: line.trimmingCharacters(in: .whitespaces),
                                          matchRange: range))
                }
            }
        }
        return hits
    }

    // MARK: - Refresh

    func refresh() {
        guard let root = rootURL else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let newTree = self.buildTree(at: root)
            let tags    = Array(self.gatherTags(newTree)).sorted()
            let refs    = self.gatherReferences(newTree)
            DispatchQueue.main.async {
                self.tree       = newTree
                self.allTags    = tags
                self.references = refs
            }
        }
    }

    private func buildTree(at url: URL) -> [FileItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return [] }
        return entries
            .filter { u in
                let name = u.lastPathComponent
                return name != ".DS_Store" && name != ".mdma_refs"
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
        var result = text
        if let rx = try? NSRegularExpression(pattern: #"```[\s\S]*?```"#) {
            result = rx.stringByReplacingMatches(in: result,
                range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "")
        }
        if let rx = try? NSRegularExpression(pattern: #"`[^`\n]+`"#) {
            result = rx.stringByReplacingMatches(in: result,
                range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "")
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
            let text = stripCode(raw)
            let ns   = text as NSString
            let len  = ns.length
            Self.contactRx.matches(in: text, range: NSRange(location: 0, length: len)).forEach { m in
                if let r = Range(m.range(at: 1), in: text) {
                    let name = String(text[r])
                    let ref  = Reference(kind: .contact(name), sourceNote: url, display: "@\(name)")
                    if !result.contains(ref) { result.append(ref) }
                }
            }
            Self.fileRefRx.matches(in: text, range: NSRange(location: 0, length: len)).forEach { m in
                if let r = Range(m.range(at: 1), in: text) {
                    let name     = String(text[r])
                    let resolved = refsFolder?.appendingPathComponent(name)
                    let ref      = Reference(kind: .fileRef(name, resolved), sourceNote: url, display: name)
                    if !result.contains(ref) { result.append(ref) }
                }
            }
            Self.linkRx.matches(in: text, range: NSRange(location: 0, length: len)).forEach { m in
                if let r = Range(m.range, in: text), let url2 = URL(string: String(text[r])) {
                    let ref = Reference(kind: .link(url2), sourceNote: url,
                                        display: url2.host ?? url2.absoluteString)
                    if !result.contains(ref) { result.append(ref) }
                }
            }
        }
        return result
    }

    // MARK: - File References

    @discardableResult
    func addFileReference(_ sourceURL: URL) -> String? {
        guard let refs = refsFolder else { return nil }
        ensureRefsFolder()
        let dest = unique(in: refs,
                          name: sourceURL.deletingPathExtension().lastPathComponent,
                          ext: sourceURL.pathExtension.isEmpty ? nil : sourceURL.pathExtension)
        do { try FileManager.default.copyItem(at: sourceURL, to: dest) }
        catch { return nil }
        refresh()
        return dest.lastPathComponent
    }

    func openFileRef(_ name: String) {
        guard let refs = refsFolder else { return }
        let url = refs.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            UIApplication.shared.open(url)
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

    func rawContent(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func save(url: URL, content: String) {
        guard !deletedURLs.contains(url) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard !self.deletedURLs.contains(url) else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    func createNote(in folder: URL? = nil, name: String = "Untitled") -> URL? {
        guard let root = rootURL else { return nil }
        let dir  = folder ?? root
        let dest = unique(in: dir, name: name, ext: "md")
        let stub = "# \(dest.deletingPathExtension().lastPathComponent)\n\n"
        try? stub.write(to: dest, atomically: true, encoding: .utf8)
        refresh()
        return dest
    }

    func createFolder(in folder: URL? = nil, name: String = "New Folder") -> URL? {
        guard let root = rootURL else { return nil }
        let dir  = folder ?? root
        let dest = unique(in: dir, name: name, ext: nil)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        refresh()
        return dest
    }

    func delete(_ url: URL) {
        deletedURLs.insert(url)
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        refresh()
    }

    @discardableResult
    func rename(_ url: URL, to newName: String) -> URL? {
        let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
        deletedURLs.insert(url)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            refresh()
            return dest
        } catch {
            deletedURLs.remove(url)
            return nil
        }
    }

    @discardableResult
    func move(_ url: URL, into folder: URL) -> URL? {
        let dest = folder.appendingPathComponent(url.lastPathComponent)
        deletedURLs.insert(url)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            refresh()
            return dest
        } catch {
            deletedURLs.remove(url)
            return nil
        }
    }

    // MARK: - Helpers

    private func ensureRefsFolder() {
        guard let refs = refsFolder else { return }
        if !FileManager.default.fileExists(atPath: refs.path) {
            try? FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        }
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

// MARK: - Notification Names

extension Notification.Name {
    static let themeDidChange   = Notification.Name("mdma.themeDidChange")
}
