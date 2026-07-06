import Foundation

// MARK: - Local LLM Session

/// Generic session handler for local LLMs (Llama, Ollama, vLLM).
/// Conforms to `AgentSession` to integrate with the provider system.
class LocalLLMSession: NSObject, AgentSession {
    // MARK: - Properties

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

    private var config: LocalLLMConfig
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var readThread: Thread?
    private let outputQueue = DispatchQueue(label: "com.lil-agents.localllm.output")

    // MARK: - Init

    init(provider: AgentProvider) {
        super.init()
        self.config = LocalLLMConfig.load(for: provider)
    }

    // MARK: - Session Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        switch config.provider {
        case .localOllama:
            startOllama()
        case .localVllm:
            startVLLM()
        case .localLlama:
            startLlama()
        default:
            onError?("Unknown local LLM provider")
            isRunning = false
        }
    }

    func send(message: String) {
        guard let proc = process, proc.isRunning, let stdin = inputPipe?.fileHandleForWriting else {
            onError?("LLM process not running")
            return
        }

        isBusy = true
        history.append(AgentMessage(role: .user, text: message))

        if let data = (message + "\n").data(using: .utf8) {
            stdin.write(data)
        }
    }

    func terminate() {
        process?.terminate()
        try? inputPipe?.fileHandleForWriting.close()
        isRunning = false
        isBusy = false
        onProcessExit?()
    }

    // MARK: - Provider-Specific Launchers

    private func startOllama() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "ollama", fallbackPaths: [
            "\(home)/.local/bin/ollama",
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/opt/ollama/bin/ollama"
        ]) { [weak self] path in
            guard let self = self else { return }
            guard let binaryPath = path else {
                self.onError?("Ollama not found. \(AgentProvider.localOllama.installInstructions)")
                self.isRunning = false
                return
            }
            self.launchOllamaProcess(binaryPath: binaryPath)
        }
    }

    private func startVLLM() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "vllm", fallbackPaths: [
            "\(home)/.venv/bin/vllm",
            "/usr/local/bin/vllm",
            "\(home)/.local/bin/vllm"
        ]) { [weak self] path in
            guard let self = self else { return }
            guard let binaryPath = path else {
                self.onError?("vLLM not found. \(AgentProvider.localVllm.installInstructions)")
                self.isRunning = false
                return
            }
            self.launchVLLMProcess(binaryPath: binaryPath)
        }
    }

    private func startLlama() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "llama", fallbackPaths: [
            "\(home)/.local/bin/llama",
            "/usr/local/bin/llama",
            "/opt/homebrew/bin/llama"
        ]) { [weak self] path in
            guard let self = self else { return }
            guard let binaryPath = path else {
                self.onError?("Llama not found. \(AgentProvider.localLlama.installInstructions)")
                self.isRunning = false
                return
            }
            self.launchLlamaProcess(binaryPath: binaryPath)
        }
    }

    // MARK: - Process Launchers

    private func launchOllamaProcess(binaryPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "run",
            config.modelName,
            "--verbose"
        ]
        proc.environment = ShellEnvironment.processEnvironment()

        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()

        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isBusy = false
                self?.onProcessExit?()
            }
        }

        do {
            try proc.run()
            self.process = proc
            onSessionReady?()
            readOutputAsync()
        } catch {
            onError?("Failed to start Ollama: \(error.localizedDescription)")
            isRunning = false
        }
    }

    private func launchVLLMProcess(binaryPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "--model", config.modelName,
            "--port", "8000",
            "--tensor-parallel-size", "1"
        ]
        proc.environment = ShellEnvironment.processEnvironment()

        outputPipe = Pipe()
        errorPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isBusy = false
                self?.onProcessExit?()
            }
        }

        do {
            try proc.run()
            self.process = proc
            // Give vLLM time to start the server
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.onSessionReady?()
            }
            readOutputAsync()
        } catch {
            onError?("Failed to start vLLM: \(error.localizedDescription)")
            isRunning = false
        }
    }

    private func launchLlamaProcess(binaryPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["-i", "-c", "2048"]
        proc.environment = ShellEnvironment.processEnvironment()

        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()

        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isBusy = false
                self?.onProcessExit?()
            }
        }

        do {
            try proc.run()
            self.process = proc
            onSessionReady?()
            readOutputAsync()
        } catch {
            onError?("Failed to start Llama: \(error.localizedDescription)")
            isRunning = false
        }
    }

    // MARK: - Output Reading

    private func readOutputAsync() {
        readThread = Thread { [weak self] in
            guard let self = self, let pipe = self.outputPipe else { return }
            let handle = pipe.fileHandleForReading

            while self.isRunning {
                let data = handle.availableData
                if data.isEmpty {
                    usleep(100_000) // 100ms
                    continue
                }

                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    DispatchQueue.main.async {
                        self.onText?(output)
                    }
                }
            }
        }
        readThread?.start()
    }
}
