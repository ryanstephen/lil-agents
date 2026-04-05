import Foundation

class GeminiSession: AgentSession {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var lineBuffer = ""
    private var currentResponseText = ""
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
        currentResponseText = ""
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

        proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        
        var env = ShellEnvironment.processEnvironment(extraPaths: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npm-global/bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        ])
        
        // Inject GEMINI_API_KEY from ~/.gemini/settings.json if it exists
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/settings.json")
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let apiKey = json["apiKey"] as? String {
            env["GEMINI_API_KEY"] = apiKey
        }
        
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        var collectedText = ""

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.process = nil

                // Process any remaining buffered content
                if !self.lineBuffer.isEmpty {
                    self.parseLine(self.lineBuffer)
                    self.lineBuffer = ""
                }

                let text = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && self.isBusy {
                    // If we got text that wasn't streamed yet (non-streaming fallback)
                    let alreadyStreamed = self.history.last?.role == .assistant
                    if !alreadyStreamed && self.currentResponseText.isEmpty {
                        self.history.append(AgentMessage(role: .assistant, text: text))
                        self.onText?(text)
                    }
                }

                // Save final response text if we tracked it
                if !self.currentResponseText.isEmpty && self.history.last?.role != .assistant {
                    self.history.append(AgentMessage(role: .assistant, text: self.currentResponseText))
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
                // Also ignore keytar errors which are common in some environments
                let isKeytarError = text.contains("Keychain initialization encountered an error")
                if !isProgressNoise && !isKeytarError {
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
            currentResponseText += text
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
                // Check for delta mode
                if let role = json["role"] as? String, role == "assistant",
                   let content = json["content"] as? String {
                    let isDelta = json["delta"] as? Bool ?? false
                    if isDelta {
                        currentResponseText += content
                        onText?(content)
                    } else if currentResponseText.isEmpty {
                        currentResponseText = content
                        onText?(content)
                    }
                } else {
                    onText?(text)
                }
            }

        case "tool_call", "function_call", "tool_use":
            let toolName = data["name"] as? String ?? json["tool_name"] as? String ?? "Tool"
            // Skip internal skill activation noise
            if toolName == "activate_skill" { return }
            let input = data["input"] as? [String: Any] ?? data["arguments"] as? [String: Any] ?? json["parameters"] as? [String: Any] ?? [:]
            let summary = formatToolSummary(toolName: toolName, params: input)
            history.append(AgentMessage(role: .toolUse, text: "\(toolName): \(summary)"))
            onToolUse?(toolName, input)

        case "tool_result", "function_result":
            let output = data["output"] as? String ?? data["result"] as? String ?? (json["output"] as? String) ?? ""
            let isError = (data["is_error"] as? Bool) ?? (json["status"] as? String == "error")
            let summary = String(output.prefix(80))
            history.append(AgentMessage(role: .toolResult, text: isError ? "ERROR: \(summary)" : summary))
            onToolResult?(summary, isError)

        case "done", "end", "complete", "turn_end", "result":
            if isBusy {
                isBusy = false
                if let result = json["result"] as? String ?? data["text"] as? String, !result.isEmpty {
                    history.append(AgentMessage(role: .assistant, text: result))
                } else if !currentResponseText.isEmpty {
                    history.append(AgentMessage(role: .assistant, text: currentResponseText))
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
                currentResponseText += text
                onText?(text)
            }
        }
    }

    private func formatToolSummary(toolName: String, params: [String: Any]) -> String {
        switch toolName {
        case "run_shell_command":
            return params["command"] as? String ?? ""
        case "read_file":
            return params["file_path"] as? String ?? ""
        case "replace", "write_file":
            return params["file_path"] as? String ?? ""
        case "glob":
            return params["pattern"] as? String ?? ""
        case "grep_search":
            return params["pattern"] as? String ?? ""
        default:
            return params.keys.sorted().prefix(3).joined(separator: ", ")
        }
    }
}
