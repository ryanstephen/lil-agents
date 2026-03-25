import Foundation

class ClaudeSession {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var lineBuffer = ""
    private(set) var isRunning = false
    private(set) var isBusy = false  // true between send() and result
    private var currentStreamingResponse = ""
    private static var claudePath: String?
    private static var shellEnvironment: [String: String]?

    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, [String: Any]) -> Void)?    // toolName, input
    var onToolResult: ((String, Bool) -> Void)?           // summary, isError
    var onSessionReady: (() -> Void)?
    var onTurnComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?

    struct Message {
        enum Role { case user, assistant, error, toolUse, toolResult }
        let role: Role
        let text: String
    }
    var history: [Message] = []

    // MARK: - Process Lifecycle

    static func resolveClaudePath(completion: @escaping (String?) -> Void) {
        if let cached = claudePath, shellEnvironment != nil {
            completion(cached)
            return
        }
        // Always capture the user's login shell environment first.
        // This is critical: Xcode's process environment has a minimal PATH that won't
        // include ~/.local/bin, /opt/homebrew/bin, nvm paths, etc.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Use -i (interactive) AND -l (login) to ensure .zshrc and .zprofile are both loaded
        proc.arguments = ["-l", "-i", "-c", "echo '---ENV_START---' && env && echo '---ENV_END---'"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        proc.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                // Parse shell environment
                if let startRange = output.range(of: "---ENV_START---\n"),
                   let endRange = output.range(of: "\n---ENV_END---") {
                    let envString = String(output[startRange.upperBound..<endRange.lowerBound])
                    var env: [String: String] = [:]
                    for line in envString.components(separatedBy: "\n") {
                        if let eqRange = line.range(of: "=") {
                            let key = String(line[line.startIndex..<eqRange.lowerBound])
                            let value = String(line[eqRange.upperBound...])
                            env[key] = value
                        }
                    }
                    shellEnvironment = env
                }

                // Now find claude: check the shell PATH first, then fallback locations
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let searchPaths = [
                    "\(home)/.local/bin/claude",
                    "\(home)/.claude/local/bin/claude",
                    "/usr/local/bin/claude",
                    "/opt/homebrew/bin/claude"
                ]

                // Check if claude is in the captured shell PATH
                if let shellPath = shellEnvironment?["PATH"] {
                    for dir in shellPath.components(separatedBy: ":") {
                        let candidate = "\(dir)/claude"
                        if FileManager.default.isExecutableFile(atPath: candidate) {
                            claudePath = candidate
                            completion(candidate)
                            return
                        }
                    }
                }

                // Fallback: check common install locations directly
                for fallback in searchPaths {
                    if FileManager.default.isExecutableFile(atPath: fallback) {
                        claudePath = fallback
                        completion(fallback)
                        return
                    }
                }

                completion(nil)
            }
        }
        do { try proc.run() } catch {
            // If shell fails entirely, still try fallback paths
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let fallbacks = [
                "\(home)/.local/bin/claude",
                "\(home)/.claude/local/bin/claude",
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude"
            ]
            for fallback in fallbacks {
                if FileManager.default.isExecutableFile(atPath: fallback) {
                    claudePath = fallback
                    completion(fallback)
                    return
                }
            }
            completion(nil)
        }
    }

    func start() {
        ClaudeSession.resolveClaudePath { [weak self] path in
            guard let self = self, let claudePath = path else {
                let msg = "Claude CLI not found.\n\nTo install, run this in Terminal:\n  curl -fsSL https://claude.ai/install.sh | sh\n\nOr download from https://claude.ai/download"
                self?.onError?(msg)
                self?.history.append(Message(role: .error, text: msg))
                return
            }
            self.launchProcess(claudePath: claudePath)
        }
    }

    private func launchProcess(claudePath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)
        proc.arguments = [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--dangerously-skip-permissions"
        ]
        proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // Use the shell environment captured from the user's login shell, not Xcode's
        // process environment. Xcode strips PATH and other vars that Claude CLI needs.
        var env = ClaudeSession.shellEnvironment ?? ProcessInfo.processInfo.environment
        // Ensure PATH always includes common locations even if shell capture failed
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let essentialPaths = [
            "\(home)/.local/bin",
            "\(home)/.local/share/claude/versions",
            "/usr/local/bin",
            "/opt/homebrew/bin"
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let missingPaths = essentialPaths.filter { !currentPath.contains($0) }
        if !missingPaths.isEmpty {
            env["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
        }
        env["TERM"] = "dumb"
        proc.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isBusy = false
                self?.onProcessExit?()
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
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.onError?(text)
                }
            }
        }

        do {
            try proc.run()
            process = proc
            inputPipe = inPipe
            outputPipe = outPipe
            errorPipe = errPipe
            isRunning = true
        } catch {
            let msg = "Failed to launch Claude CLI.\n\nMake sure Claude Code is installed and up to date:\n  curl -fsSL https://claude.ai/install.sh | sh\n\nError: \(error.localizedDescription)"
            onError?(msg)
            history.append(Message(role: .error, text: msg))
        }
    }

    func send(message: String) {
        guard isRunning, let pipe = inputPipe else { return }
        isBusy = true
        history.append(Message(role: .user, text: message))

        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": message
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else { return }
        let line = jsonStr + "\n"
        pipe.fileHandleForWriting.write(line.data(using: .utf8)!)
    }

    func terminate() {
        process?.terminate()
        isRunning = false
    }

    // MARK: - NDJSON Parsing

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
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = json["type"] as? String ?? ""

        switch type {
        case "system":
            let subtype = json["subtype"] as? String ?? ""
            if subtype == "init" {
                onSessionReady?()
            }

        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "text", let text = block["text"] as? String {
                        currentStreamingResponse += text
                        onText?(text)
                    } else if blockType == "tool_use" {
                        let toolName = block["name"] as? String ?? "Tool"
                        let input = block["input"] as? [String: Any] ?? [:]
                        let summary = formatToolSummary(toolName: toolName, input: input)
                        history.append(Message(role: .toolUse, text: "\(toolName): \(summary)"))
                        onToolUse?(toolName, input)
                    }
                }
            }

        case "user":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "tool_result" {
                        let isError = block["is_error"] as? Bool ?? false
                        var summary = ""
                        if let resultInfo = json["tool_use_result"] as? [String: Any] {
                            if let text = resultInfo["type"] as? String, text == "text" {
                                if let file = resultInfo["file"] as? [String: Any],
                                   let path = file["filePath"] as? String {
                                    let lines = file["totalLines"] as? Int ?? 0
                                    summary = "\(path) (\(lines) lines)"
                                }
                            }
                        } else if let resultStr = json["tool_use_result"] as? String {
                            summary = String(resultStr.prefix(80))
                        }
                        if summary.isEmpty {
                            if let contentStr = block["content"] as? String {
                                summary = String(contentStr.prefix(80))
                            }
                        }
                        history.append(Message(role: .toolResult, text: isError ? "ERROR: \(summary)" : summary))
                        onToolResult?(summary, isError)
                    }
                }
            }

        case "result":
            isBusy = false
            let responseText = currentStreamingResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if !responseText.isEmpty {
                history.append(Message(role: .assistant, text: responseText))
            } else if let result = json["result"] as? String, !result.isEmpty {
                history.append(Message(role: .assistant, text: result))
            }
            currentStreamingResponse = ""
            onTurnComplete?()

        default:
            break
        }
    }

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
