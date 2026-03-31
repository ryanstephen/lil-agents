import Foundation

class QoderSession: AgentSession {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var lineBuffer = ""
    private(set) var isRunning = false
    private(set) var isBusy = false
    private var isFirstTurn = true
    private static var binaryPath: String?

    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, [String: Any]) -> Void)?
    var onToolResult: ((String, Bool) -> Void)?
    var onSessionReady: (() -> Void)?
    var onTurnComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?

    var history: [AgentMessage] = []

    // MARK: - Lifecycle

    func start() {
        if Self.binaryPath != nil {
            isRunning = true
            onSessionReady?()
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "qodercli", fallbackPaths: [
            "\(home)/.local/bin/qodercli",
            "\(home)/.qoder/bin/qodercli",
            "/usr/local/bin/qodercli",
            "/opt/homebrew/bin/qodercli"
        ]) { [weak self] path in
            guard let self = self else { return }
            if let binaryPath = path {
                Self.binaryPath = binaryPath
                self.isRunning = true
                self.onSessionReady?()
            } else {
                let msg = "Qoder CLI not found.\n\n\(AgentProvider.qoder.installInstructions)"
                self.onError?(msg)
                self.history.append(AgentMessage(role: .error, text: msg))
            }
        }
    }

    func send(message: String) {
        guard isRunning, let binaryPath = Self.binaryPath else { return }
        isBusy = true
        history.append(AgentMessage(role: .user, text: message))
        lineBuffer = ""

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)

        // qodercli --yolo -p "message" --output-format stream-json
        // For multi-turn, inject conversation context into the prompt
        let prompt = isFirstTurn ? message : buildPrompt(with: message)
        proc.arguments = ["--yolo", "-p", prompt, "--output-format", "stream-json"]

        proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        proc.environment = ShellEnvironment.processEnvironment(extraPaths: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qoder/bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        ])

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        var collectedText = ""

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.process = nil

                let text = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && self.isBusy {
                    // If we got text that wasn't streamed yet (non-streaming fallback)
                    let alreadyStreamed = self.history.last?.role == .assistant
                    if !alreadyStreamed {
                        self.history.append(AgentMessage(role: .assistant, text: text))
                        self.onText?(text)
                    }
                }

                if self.isBusy {
                    self.isBusy = false
                    self.onTurnComplete?()
                }
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    collectedText += text
                    // Try to parse as JSONL first, fall back to streaming plain text
                    self.processOutput(text)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // Qoder CLI may write progress/status to stderr — filter noise
            if let text = String(data: data, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // Only surface actual errors, not progress indicators
                let isProgressNoise = trimmed.hasPrefix("✓") || trimmed.hasPrefix("→") ||
                                      trimmed.hasPrefix("◆") || trimmed.hasPrefix("⠋") ||
                                      trimmed.hasPrefix("⠙") || trimmed.hasPrefix("⠹") ||
                                      trimmed.hasPrefix("⠸") || trimmed.hasPrefix("⠼") ||
                                      trimmed.hasPrefix("⠴") || trimmed.hasPrefix("⠦") ||
                                      trimmed.hasPrefix("⠧") || trimmed.hasPrefix("⠇") ||
                                      trimmed.hasPrefix("⠏") || trimmed.isEmpty
                if !isProgressNoise {
                    DispatchQueue.main.async {
                        self?.onError?(text)
                    }
                }
            }
        }

        do {
            try proc.run()
            process = proc
            outputPipe = outPipe
            errorPipe = errPipe
            isFirstTurn = false
        } catch {
            isBusy = false
            let msg = "Failed to launch Qoder CLI: \(error.localizedDescription)"
            onError?(msg)
            history.append(AgentMessage(role: .error, text: msg))
        }
    }

    func terminate() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        isRunning = false
        isBusy = false
    }

    // MARK: - Multi-turn Prompt Building

    private func buildPrompt(with message: String) -> String {
        var context = "Conversation so far (for context):\n"
        for msg in history.dropLast() {
            switch msg.role {
            case .user:
                context += "User: \(msg.text)\n"
            case .assistant:
                context += "Assistant: \(msg.text)\n"
            case .toolUse:
                context += "Tool: \(msg.text)\n"
            case .toolResult:
                context += "Tool result: \(msg.text)\n"
            case .error:
                break
            }
        }
        context += "\n---\nUser (follow-up): \(message)"
        return context
    }

    // MARK: - Output Parsing

    private var didReceiveJsonLine = false

    private func processOutput(_ text: String) {
        lineBuffer += text
        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
            lineBuffer = String(lineBuffer[newlineRange.upperBound...])
            if !line.isEmpty {
                parseLine(line)
            }
        }
    }

    private func parseLine(_ line: String) {
        // Attempt JSON parse
        if let rawData = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
            didReceiveJsonLine = true
            handleJsonEvent(json)
            return
        }

        // Plain text fallback: stream each line as assistant text
        if !didReceiveJsonLine {
            let text = line + "\n"
            onText?(text)
        }
    }

    private func handleJsonEvent(_ json: [String: Any]) {
        let type = json["type"] as? String ?? json["event"] as? String ?? ""

        switch type {
        case "text_delta", "text", "content", "delta", "message":
            let text = json["text"] as? String ?? json["content"] as? String ?? json["delta"] as? String ?? ""
            if !text.isEmpty {
                onText?(text)
            }

        case "tool_call", "tool_use", "tool":
            let toolName = json["name"] as? String ?? json["tool_name"] as? String ?? "Tool"
            let input = json["input"] as? [String: Any] ?? json["arguments"] as? [String: Any] ?? json["parameters"] as? [String: Any] ?? [:]
            history.append(AgentMessage(role: .toolUse, text: "\(toolName): \(input["command"] as? String ?? input["path"] as? String ?? toolName)"))
            onToolUse?(toolName, input)

        case "tool_result", "tool_output", "tool_response":
            let output = json["output"] as? String ?? json["result"] as? String ?? json["content"] as? String ?? ""
            let isError = (json["is_error"] as? Bool) ?? (json["error"] as? String != nil)
            let summary = String(output.prefix(80))
            history.append(AgentMessage(role: .toolResult, text: isError ? "ERROR: \(summary)" : summary))
            onToolResult?(summary, isError)

        case "done", "end", "complete", "turn_complete", "turn_end":
            if isBusy {
                isBusy = false
                if let result = json["result"] as? String ?? json["text"] as? String, !result.isEmpty {
                    history.append(AgentMessage(role: .assistant, text: result))
                }
                onTurnComplete?()
            }

        case "error":
            let msg = json["message"] as? String ?? json["error"] as? String ?? "Unknown Qoder error"
            onError?(msg)
            history.append(AgentMessage(role: .error, text: msg))

        default:
            // Forward any text content we find
            if let text = json["text"] as? String ?? json["content"] as? String, !text.isEmpty {
                onText?(text)
            }
        }
    }
}
