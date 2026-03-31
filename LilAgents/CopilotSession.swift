import Foundation

class CopilotSession: AgentSession {
    let workingDirectoryURL: URL
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var lineBuffer = ""
    private(set) var isRunning = false
    private(set) var isBusy = false
    private var isFirstTurn = true
    private var useJsonOutput = true
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
        ShellEnvironment.findBinary(name: "copilot", fallbackPaths: [
            "\(home)/.local/bin/copilot",
            "\(home)/.npm-global/bin/copilot",
            "/usr/local/bin/copilot",
            "/opt/homebrew/bin/copilot"
        ]) { [weak self] path in
            guard let self = self else { return }
            if let binaryPath = path {
                Self.binaryPath = binaryPath
                self.isRunning = true
                self.onSessionReady?()
            } else {
                let msg = "Copilot CLI not found.\n\n\(AgentProvider.copilot.installInstructions)"
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

        var args = ["-p", message]
        if !isFirstTurn {
            args.insert("--continue", at: 0)
        }
        if useJsonOutput {
            args.append(contentsOf: ["--output-format", "json"])
        } else {
            args.append("-s")
        }
        args.append("--allow-all")
        proc.arguments = args

        proc.currentDirectoryURL = workingDirectoryURL
        proc.environment = ShellEnvironment.processEnvironment(extraPaths: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".npm-global/bin").path
        ])

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        var collectedPlainText = ""

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.process = nil

                if self.useJsonOutput {
                    if !self.lineBuffer.isEmpty {
                        self.parseLine(self.lineBuffer)
                        self.lineBuffer = ""
                    }
                } else {
                    let text = collectedPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
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
                    if self?.useJsonOutput == true {
                        self?.processOutput(text)
                    } else {
                        collectedPlainText += text
                    }
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.onError?(text)
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
            let msg = "Failed to launch Copilot CLI: \(error.localizedDescription)"
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

    // MARK: - JSONL Parsing

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
        guard let rawData = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
            if history.count <= 1 {
                useJsonOutput = false
                let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    history.append(AgentMessage(role: .assistant, text: text))
                    onText?(text)
                }
            }
            return
        }

        // Skip ephemeral events, but still handle streaming deltas
        if json["ephemeral"] as? Bool == true {
            let type = json["type"] as? String ?? ""
            if type == "assistant.message_delta",
               let data = json["data"] as? [String: Any],
               let delta = data["deltaContent"] as? String, !delta.isEmpty {
                onText?(delta)
            }
            return
        }

        let type = json["type"] as? String ?? ""
        let data = json["data"] as? [String: Any] ?? [:]

        switch type {
        case "assistant.message":
            let content = data["content"] as? String ?? ""
            if !content.isEmpty {
                history.append(AgentMessage(role: .assistant, text: content))
            }

        case "assistant.turn_end":
            isBusy = false
            onTurnComplete?()

        case "result":
            isBusy = false
            onTurnComplete?()

        case "assistant.tool_call":
            let toolName = data["name"] as? String ?? data["tool"] as? String ?? "Tool"
            let input = data["input"] as? [String: Any] ?? data["arguments"] as? [String: Any] ?? [:]
            let command = input["command"] as? String ?? ""
            let displayName = command.isEmpty ? toolName : "Bash"
            let summary = command.isEmpty ? toolName : command
            history.append(AgentMessage(role: .toolUse, text: "\(displayName): \(summary)"))
            onToolUse?(displayName, input)

        case "assistant.tool_result":
            let output = data["output"] as? String ?? data["result"] as? String ?? ""
            let isError = (data["is_error"] as? Bool) ?? (data["status"] as? String == "error")
            let summary = String(output.prefix(80))
            history.append(AgentMessage(role: .toolResult, text: isError ? "ERROR: \(summary)" : summary))
            onToolResult?(summary, isError)

        case "error":
            let msg = data["message"] as? String ?? data["error"] as? String ?? "Unknown error"
            onError?(msg)
            history.append(AgentMessage(role: .error, text: msg))

        default:
            break
        }
    }
}
