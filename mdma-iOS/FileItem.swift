import Foundation

struct FileItem: Identifiable, Hashable {
    let url: URL
    var children: [FileItem]?

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var displayName: String { isDirectory ? name : url.deletingPathExtension().lastPathComponent }
    var isDirectory: Bool { children != nil }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}
