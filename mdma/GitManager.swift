import Foundation
import Combine

// MARK: - Status

enum GitFileStatus {
    case modified    // M  — changed in working tree
    case untracked   // ?? — new file not yet tracked
    case staged      // A  — staged for commit
    case deleted     // D  — deleted
    case renamed     // R  — renamed/moved
}

// MARK: - GitManager

final class GitManager: ObservableObject {

    static let shared = GitManager()

    @Published var isRepo:          Bool                    = false
    @Published var currentBranch:   String                  = ""
    @Published var statuses:        [String: GitFileStatus] = [:]   // relative path → status
    @Published var uncommittedCount: Int                    = 0

    private var rootURL:       URL?
    private var refreshTimer:  Timer?

    private init() {}

    // MARK: - Configuration

    func configure(rootURL: URL) {
        self.rootURL = rootURL
        checkRepo()
    }

    private func checkRepo() {
        guard let root = rootURL else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            let has = FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
            DispatchQueue.main.async {
                self?.isRepo = has
                if has {
                    self?.refresh()
                    self?.startTimer()
                } else {
                    self?.stopTimer()
                }
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard let root = rootURL, isRepo else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let parsed = self.parseStatus(root: root)
            let branch = self.readBranch(root: root)
            DispatchQueue.main.async {
                self.statuses        = parsed
                self.currentBranch   = branch
                self.uncommittedCount = parsed.count
            }
        }
    }

    // MARK: - Commit helpers

    /// Stage and commit a single file (used by auto-commit on save).
    func commitFile(_ url: URL, message: String) {
        guard let root = rootURL, isRepo else { return }
        let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.shell("git add \"\(rel)\"", in: root)
            self?.shell("git commit -m \"\(message)\"", in: root)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
        }
    }

    /// Stage all changes and commit with the given message.
    func commitAll(message: String) {
        guard let root = rootURL, isRepo else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.shell("git add -A", in: root)
            self?.shell("git commit -m \"\(message)\"", in: root)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Parsing

    private func parseStatus(root: URL) -> [String: GitFileStatus] {
        guard let out = shell("git status --porcelain", in: root) else { return [:] }
        var result: [String: GitFileStatus] = [:]
        for raw in out.components(separatedBy: "\n") {
            guard raw.count >= 3 else { continue }
            let xy   = String(raw.prefix(2))
            var path = String(raw.dropFirst(3))
            // Handle renames: "R old -> new" — take the new name
            if xy.contains("R"), let arrow = path.range(of: " -> ") {
                path = String(path[arrow.upperBound...])
            }
            let status: GitFileStatus
            if xy == "??" || xy == "!!" {
                status = .untracked
            } else if xy.hasPrefix("A") || xy.hasSuffix("A") {
                status = .staged
            } else if xy.contains("D") {
                status = .deleted
            } else if xy.contains("R") {
                status = .renamed
            } else {
                status = .modified
            }
            result[path] = status
        }
        return result
    }

    private func readBranch(root: URL) -> String {
        (shell("git rev-parse --abbrev-ref HEAD", in: root) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Shell

    @discardableResult
    private func shell(_ command: String, in dir: URL) -> String? {
        let proc = Process()
        proc.launchPath       = "/bin/bash"
        proc.arguments        = ["-c", command]
        proc.currentDirectoryURL = dir
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError  = err
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
