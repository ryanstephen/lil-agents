import Foundation

/// Observes an active Claude Code session by watching its event file,
/// and can send messages into the session via an inbox mechanism.
class LiveSession: AgentSession {
    private(set) var isRunning = false
    private(set) var isBusy = false
    var history: [AgentMessage] = []

    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, [String: Any]) -> Void)?
    var onToolResult: ((String, Bool) -> Void)?
    var onSessionReady: (() -> Void)?
    var onTurnComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?

    let sessionId: String
    let projectName: String
    private var fileHandle: FileHandle?
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var lineBuffer = ""
    private var pollTimer: Timer?

    private static let baseDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/lil-agents"
    }()

    static var sessionsDir: String { "\(baseDir)/sessions" }
    private static var inboxDir: String { "\(baseDir)/inbox" }

    init(sessionId: String, projectName: String = "") {
        self.sessionId = sessionId
        self.projectName = projectName
    }

    // MARK: - Session Discovery

    struct DiscoveredSession {
        let id: String
        let cwd: String
        let startedAt: Date
        let lastEvent: Date

        var projectName: String {
            (cwd as NSString).lastPathComponent
        }

        var age: String {
            let seconds = Int(Date().timeIntervalSince(lastEvent))
            if seconds < 60 { return "\(seconds)s ago" }
            let minutes = seconds / 60
            if minutes < 60 { return "\(minutes)m ago" }
            return "\(minutes / 60)h ago"
        }

        var isStale: Bool {
            Date().timeIntervalSince(lastEvent) > 600 // 10 minutes
        }
    }

    static func discoverSessions() -> [DiscoveredSession] {
        let fm = FileManager.default
        let dir = sessionsDir

        // Ensure dir exists
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }

        var sessions: [DiscoveredSession] = []
        for file in files where file.hasSuffix(".meta") {
            let path = "\(dir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["session_id"] as? String else { continue }

            let cwd = json["cwd"] as? String ?? "~"
            let startedMs = json["started_at"] as? Double ?? 0
            let lastEventMs = json["last_event"] as? Double ?? 0

            let session = DiscoveredSession(
                id: id,
                cwd: cwd,
                startedAt: Date(timeIntervalSince1970: startedMs / 1000),
                lastEvent: Date(timeIntervalSince1970: lastEventMs / 1000)
            )

            if !session.isStale {
                sessions.append(session)
            }
        }

        return sessions.sorted { $0.lastEvent > $1.lastEvent }
    }

    // MARK: - Lifecycle

    func start() {
        let sessionFile = "\(Self.sessionsDir)/\(sessionId).jsonl"

        guard FileManager.default.fileExists(atPath: sessionFile) else {
            onError?("Session file not found. Is the Claude Code hook installed?")
            return
        }

        guard let handle = FileHandle(forReadingAtPath: sessionFile) else {
            onError?("Cannot open session file.")
            return
        }

        fileHandle = handle
        isRunning = true

        // Replay recent events for context
        replayRecentEvents(from: sessionFile)

        // Seek to end for live watching
        handle.seekToEndOfFile()

        // Watch for file changes using DispatchSource
        let fd = handle.fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.readNewEvents()
        }

        source.setCancelHandler { [weak self] in
            self?.fileHandle?.closeFile()
            self?.fileHandle = nil
        }

        dispatchSource = source
        source.resume()

        // Also poll periodically as a fallback (DispatchSource can miss appends)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.readNewEvents()
        }

        onSessionReady?()
    }

    private func replayRecentEvents(from path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let recent = lines.suffix(15)
        for line in recent {
            parseLine(line)
        }
    }

    private func readNewEvents() {
        guard let handle = fileHandle else { return }

        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

        lineBuffer += text
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            if !line.isEmpty {
                parseLine(line)
            }
        }
    }

    // MARK: - Event Parsing

    private func parseLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let hook = json["hook"] as? String ?? ""
        let tool = json["tool"] as? String
        let input = json["input"] as? [String: Any]
        let output = json["output"] as? String

        switch hook {
        case "PreToolUse":
            guard let toolName = tool else { break }
            isBusy = true
            let summary = formatToolSummary(toolName: toolName, input: input ?? [:])
            history.append(AgentMessage(role: .toolUse, text: "\(toolName): \(summary)"))
            onToolUse?(toolName, input ?? [:])

        case "PostToolUse":
            let isError = false
            let summary = output.map { String($0.prefix(80)) } ?? ""
            let toolName = tool ?? "Tool"
            history.append(AgentMessage(role: .toolResult, text: summary))
            onToolResult?(summary, isError)
            // After a tool completes, mark not busy briefly
            // (will become busy again on next PreToolUse)
            isBusy = false
            onTurnComplete?()

        case "SessionStart":
            let event = json["event"] as? String ?? "started"
            let text = "session \(event)"
            history.append(AgentMessage(role: .assistant, text: text))
            onText?(text + "\n")

        case "Notification":
            if let notification = json["notification"] as? String {
                history.append(AgentMessage(role: .assistant, text: notification))
                onText?(notification + "\n")
            }

        default:
            if let text = json["text"] as? String {
                history.append(AgentMessage(role: .assistant, text: text))
                onText?(text)
            }
        }
    }

    // MARK: - Send (Inbox)

    func send(message: String) {
        let fm = FileManager.default
        let inboxDir = Self.inboxDir

        try? fm.createDirectory(atPath: inboxDir, withIntermediateDirectories: true)

        let inboxFile = "\(inboxDir)/\(sessionId).jsonl"
        let payload: [String: Any] = [
            "text": message,
            "from": "lil-agents",
            "ts": Int(Date().timeIntervalSince1970 * 1000)
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else { return }

        let line = jsonStr + "\n"

        if fm.fileExists(atPath: inboxFile) {
            if let handle = FileHandle(forWritingAtPath: inboxFile) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            }
        } else {
            try? line.write(toFile: inboxFile, atomically: true, encoding: .utf8)
        }

        history.append(AgentMessage(role: .user, text: message))
    }

    func terminate() {
        pollTimer?.invalidate()
        pollTimer = nil
        dispatchSource?.cancel()
        dispatchSource = nil
        fileHandle?.closeFile()
        fileHandle = nil
        isRunning = false
    }

    // MARK: - Helpers

    private func formatToolSummary(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            return input["command"] as? String ?? ""
        case "Read":
            return input["file_path"] as? String ?? ""
        case "Edit", "Write":
            return input["file_path"] as? String ?? ""
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "Grep":
            return input["pattern"] as? String ?? ""
        default:
            if let desc = input["description"] as? String { return desc }
            return input.keys.sorted().prefix(3).joined(separator: ", ")
        }
    }
}
