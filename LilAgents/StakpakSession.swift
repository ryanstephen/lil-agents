import Foundation

class StakpakSession: AgentSession {
    private var process: Process?
    private var currentResponseText = ""
    private(set) var isRunning = false
    private(set) var isBusy = false
    private static var binaryPath: String?

    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, [String: Any]) -> Void)?
    var onToolResult: ((String, Bool) -> Void)?
    var onSessionReady: (() -> Void)?
    var onTurnComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?

    var history: [AgentMessage] = []

    // MARK: - Process Lifecycle

    func start() {
        if let cached = Self.binaryPath {
            isRunning = true
            DispatchQueue.main.async { self.onSessionReady?() }
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "stakpak", fallbackPaths: [
            "\(home)/.local/bin/stakpak",
            "/usr/local/bin/stakpak",
            "/opt/homebrew/bin/stakpak"
        ]) { [weak self] path in
            guard let self = self, let binaryPath = path else {
                let msg = "Stakpak CLI not found.\n\n\(AgentProvider.stakpak.installInstructions)"
                self?.onError?(msg)
                self?.history.append(AgentMessage(role: .error, text: msg))
                return
            }
            Self.binaryPath = binaryPath
            self.isRunning = true
            self.onSessionReady?()
        }
    }

    func send(message: String) {
        guard isRunning, let binaryPath = Self.binaryPath else { return }

        isBusy = true
        currentResponseText = ""
        history.append(AgentMessage(role: .user, text: message))

        // Build prompt: prepend conversation history so stakpak has context
        var prompt = ""
        let contextMessages = history.dropLast() // exclude the message we just added
        if !contextMessages.isEmpty {
            prompt += "Here is our conversation so far:\n"
            for msg in contextMessages {
                switch msg.role {
                case .user:
                    prompt += "User: \(msg.text)\n"
                case .assistant:
                    prompt += "Assistant: \(msg.text)\n"
                case .error, .toolUse, .toolResult:
                    break
                }
            }
            prompt += "\nNow respond to:\n"
        }
        prompt += message

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(home)/.stakpak/config.toml"
        proc.arguments = ["-a", "--max-steps", "20", "--config", configPath, prompt]
        proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        proc.environment = ShellEnvironment.processEnvironment(extraPaths: ["/opt/homebrew/bin"])

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isBusy = false
                // Clean the full buffered response: filter chrome lines, strip box prefix
                let lines = self.currentResponseText.components(separatedBy: "\n")
                let cleanLines = lines
                    .filter { !self.isChromeLine($0) }
                    .map { self.stripBoxPrefix($0) }
                let finalText = cleanLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalText.isEmpty {
                    self.history.append(AgentMessage(role: .assistant, text: finalText))
                }
                self.currentResponseText = ""
                self.onTurnComplete?()
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.processOutput(text)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // Stakpak writes progress/status info to stderr — swallow it silently
            // so it doesn't bleed into the chat view. Uncomment the line below
            // to surface stderr errors to the user if needed.
            // if let text = String(data: data, encoding: .utf8) {
            //     DispatchQueue.main.async { self?.onError?(text) }
            // }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            let msg = "Failed to launch Stakpak.\n\n\(AgentProvider.stakpak.installInstructions)\n\nError: \(error.localizedDescription)"
            onError?(msg)
            history.append(AgentMessage(role: .error, text: msg))
            isBusy = false
        }
    }

    func terminate() {
        process?.terminate()
        process = nil
        isRunning = false
        isBusy = false
    }

    // MARK: - Output Processing

    private func processOutput(_ text: String) {
        // Strip ANSI escape codes (stakpak outputs colored terminal text)
        let clean = stripANSI(text)
        // Buffer all output, then clean up chrome in terminationHandler
        currentResponseText += clean
        // Stream lines that aren't UI chrome immediately
        for line in clean.components(separatedBy: "\n") {
            if !isChromeLine(line) {
                let stripped = stripBoxPrefix(line)
                onText?(stripped + "\n")
            }
        }
    }

    /// Returns true for lines that are stakpak UI chrome, not actual response content.
    private func isChromeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Box-drawing borders: ┌─ Final Agent Response, │ content, └───
        if trimmed.hasPrefix("┌") || trimmed.hasPrefix("└") { return true }
        // Session Usage block
        if trimmed == "Session Usage" { return false } // let it fall through to footer filter
        // "To resume, run:" and session ID lines
        if trimmed.hasPrefix("To resume, run:") { return true }
        if trimmed.hasPrefix("stakpak -s ") { return true }
        if trimmed.hasPrefix("Session ID:") { return true }
        // Token usage table lines (start with Model, Prompt tokens, etc.)
        let usageLabels = ["Model", "Prompt tokens", "├─", "└─", "Completion tokens", "Total tokens", "Session Usage"]
        if usageLabels.contains(where: { trimmed.hasPrefix($0) }) { return true }
        // Stakpak internal warnings
        if trimmed.hasPrefix("[warning]") || trimmed.hasPrefix("[info]") { return true }
        return false
    }

    /// Remove the leading "│ " box prefix from content lines inside the response box.
    private func stripBoxPrefix(_ line: String) -> String {
        var s = line
        // Remove leading │ and optional space
        if s.hasPrefix("│ ") { s = String(s.dropFirst(2)) }
        else if s.hasPrefix("│") { s = String(s.dropFirst(1)) }
        return s
    }

    /// Remove ANSI escape sequences from terminal output.
    private func stripANSI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\x1B(?:\\[[0-9;]*[A-Za-z]|[^\\[])") else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
