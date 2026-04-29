import Foundation

struct NoteFile: Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var content: String
    var url: URL?
    var lastModified: Date = Date()

    init(title: String = "Untitled", content: String = "") {
        self.title = title
        self.content = content
    }

    static func == (lhs: NoteFile, rhs: NoteFile) -> Bool {
        lhs.url == rhs.url && lhs.url != nil
            ? lhs.url == rhs.url
            : lhs.id == rhs.id
    }
}
