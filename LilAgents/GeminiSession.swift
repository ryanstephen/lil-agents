import Foundation

class GeminiSession: AgentSession {
    let workingDirectoryURL: URL
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var lineBuffer = ""
    private(set) var isRunning = false
    private(set) var isBusy = false
    private var isFirstTurn = true
    private static var binaryPath: String?

    init(workingDirectoryURL: URL) {
        self.workingDirectoryURL = workingDirectoryURL
    }

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
        ShellEnvironment.findBinary(name: "gemini", fallbackPaths: [
            "\(home)/.local/bin/gemini",
            "\(home)/.npm-global/bin/gemini",
            "/usr/local/bin/gemini",
            "/opt/homebrew/bin/gemini"
        ]) { [weak self] path in
            guard let self = self else { return }
            if let binaryPath = path {
                Self.binaryPath = binaryPath
                self.isRunning = true
                self.onSessionReady?()
            } else {
                let msg = "Gemini CLI not found.\n\n\(AgentProvider.gemini.installInstructions)"
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

        // gemini --yolo -p "message" for agentic use
        // --continue for subsequent turns (if supported by installed version)
        var args: [String] = ["--yolo", "-p", message]
        if !isFirstTurn {
            args = ["--yolo", "--continue", "-p", message]
        }
        proc.arguments = args

        proc.currentDirectoryURL = workingDirectoryURL
        proc.environment = ShellEnvironment.processEnvironment(extraPaths: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npm-global/bin").path,
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
            // Gemini CLI may write progress/status to stderr — filter noise
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
            let msg = "Failed to launch Gemini CLI: \(error.localizedDescription)"
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

    // MARK: - Output Parsing

    // Gemini CLI may emit JSONL or plain text depending on version/flags.
    // We try JSONL first, fall back to treating output as plain streaming text.
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
        let data = json["data"] as? [String: Any] ?? json

        switch type {
        case "content", "text", "delta", "message":
            let text = data["text"] as? String ?? data["content"] as? String ?? json["text"] as? String ?? ""
            if !text.isEmpty {
                onText?(text)
            }

        case "tool_call", "function_call":
            let toolName = data["name"] as? String ?? "Tool"
            let input = data["input"] as? [String: Any] ?? data["arguments"] as? [String: Any] ?? [:]
            history.append(AgentMessage(role: .toolUse, text: "\(toolName): \(input["command"] as? String ?? toolName)"))
            onToolUse?(toolName, input)

        case "tool_result", "function_result":
            let output = data["output"] as? String ?? data["result"] as? String ?? ""
            let isError = (data["is_error"] as? Bool) ?? false
            let summary = String(output.prefix(80))
            history.append(AgentMessage(role: .toolResult, text: isError ? "ERROR: \(summary)" : summary))
            onToolResult?(summary, isError)

        case "done", "end", "complete", "turn_end":
            if isBusy {
                isBusy = false
                if let result = json["result"] as? String ?? data["text"] as? String, !result.isEmpty {
                    history.append(AgentMessage(role: .assistant, text: result))
                }
                onTurnComplete?()
            }

        case "error":
            let msg = data["message"] as? String ?? data["error"] as? String ?? "Unknown Gemini error"
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
