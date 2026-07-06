import Foundation

// MARK: - Provider

enum AgentProvider: String, CaseIterable {
    case claude, codex, copilot, gemini, opencode, openclaw
    case localLlama, localOllama, localVllm

    private static let defaultsKey = "selectedProvider"

    static var current: AgentProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? "claude"
            return AgentProvider(rawValue: raw) ?? .claude
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var displayName: String {
        switch self {
        case .claude:      return "Claude"
        case .codex:       return "Codex"
        case .copilot:     return "Copilot"
        case .gemini:      return "Gemini"
        case .opencode:    return "OpenCode"
        case .openclaw:    return "OpenClaw"
        case .localLlama:  return "Local • Llama"
        case .localOllama: return "Local • Ollama"
        case .localVllm:   return "Local • vLLM"
        }
    }

    var inputPlaceholder: String {
        "Ask \(displayName)..."
    }

    /// Returns provider name styled per theme format.
    func titleString(format: TitleFormat) -> String {
        switch format {
        case .uppercase:      return displayName.uppercased()
        case .lowercaseTilde: return displayName.lowercased()
        case .capitalized:    return displayName
        }
    }

    var binaryName: String {
        switch self {
        case .claude:      return "claude"
        case .codex:       return "codex"
        case .copilot:     return "copilot"
        case .gemini:      return "gemini"
        case .opencode:    return "opencode"
        case .openclaw:    return "openclaw"
        case .localLlama:  return "llama"
        case .localOllama: return "ollama"
        case .localVllm:   return "vllm"
        }
    }

    /// Cache of provider availability, populated by `detectAvailableProviders`.
    private(set) static var availability: [AgentProvider: Bool] = [:]

    /// Scan PATH for all provider binaries and call completion when done.
    static func detectAvailableProviders(completion: @escaping () -> Void) {
        let all = AgentProvider.allCases
        let group = DispatchGroup()

        for provider in all {
            // OpenClaw is network-based, not a local binary
            if provider == .openclaw {
                availability[provider] = OpenClawConfig.load().authToken.isEmpty == false
                continue
            }

            group.enter()
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            var fallbackPaths = [
                "\(home)/.local/bin/\(provider.binaryName)",
                "/usr/local/bin/\(provider.binaryName)",
                "/opt/homebrew/bin/\(provider.binaryName)"
            ]

            // Add extra paths for local LLMs
            switch provider {
            case .localOllama:
                fallbackPaths.append("/opt/ollama/bin/ollama")
                fallbackPaths.append("\(home)/.ollama/bin/ollama")
            case .localVllm:
                fallbackPaths.append("\(home)/.venv/bin/vllm")
                fallbackPaths.append("/usr/local/bin/vllm")
            default:
                break
            }

            ShellEnvironment.findBinary(name: provider.binaryName, fallbackPaths: fallbackPaths) { path in
                availability[provider] = path != nil
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion()
        }
    }

    var isAvailable: Bool {
        if self == .openclaw { return OpenClawConfig.load().authToken.isEmpty == false }
        return AgentProvider.availability[self] ?? false
    }

    /// Returns the first available provider, or `.claude` as fallback.
    static var firstAvailable: AgentProvider {
        allCases.first(where: { $0.isAvailable }) ?? .claude
    }

    var installInstructions: String {
        switch self {
        case .claude:
            return "To install, run this in Terminal:\n  curl -fsSL https://claude.ai/install.sh | sh\n\nOr download from https://claude.ai/download"
        case .codex:
            return "To install, run this in Terminal:\n  npm install -g @openai/codex"
        case .copilot:
            return "To install, run this in Terminal:\n  brew install copilot-cli\n\nOr: npm install -g @github/copilot-cli"
        case .gemini:
            return "To install, run this in Terminal:\n  npm install -g @google/gemini-cli\n\nThen authenticate:\n  gemini auth"
        case .opencode:
            return "To install, run this in Terminal:\n  curl -fsSL https://opencode.ai/install | bash"
        case .openclaw:
            return "OpenClaw is a self-hosted AI gateway.\n\nInstall: npm install -g openclaw\nStart:   openclaw gateway run\n\nDocs: https://docs.openclaw.ai"
        case .localLlama:
            return "To install Llama locally:\n\n1. Download from: https://github.com/ggerganov/llama.cpp\n2. Build: make\n3. Place binary in /usr/local/bin or ~/.local/bin\n\nOr use Homebrew:\n  brew install llama.cpp"
        case .localOllama:
            return "To install Ollama:\n\n1. Download from: https://ollama.ai\n2. Install the app\n3. Run: ollama serve (in background)\n4. Test: ollama run llama2\n\nOr with Homebrew:\n  brew install ollama"
        case .localVllm:
            return "To install vLLM:\n\n1. Create virtual env: python3 -m venv ~/.venv\n2. Activate: source ~/.venv/bin/activate\n3. Install: pip install vllm\n4. Start server: python -m vllm.entrypoints.openai.api_server"
        }
    }

    func createSession() -> any AgentSession {
        switch self {
        case .claude:      return ClaudeSession()
        case .codex:       return CodexSession()
        case .copilot:     return CopilotSession()
        case .gemini:      return GeminiSession()
        case .opencode:    return OpenCodeSession()
        case .openclaw:    return OpenClawSession()
        case .localLlama:  return LocalLLMSession(provider: .localLlama)
        case .localOllama: return LocalLLMSession(provider: .localOllama)
        case .localVllm:   return LocalLLMSession(provider: .localVllm)
        }
    }
}

// MARK: - Local LLM Configuration

/// Stores and manages per-provider configuration for local LLMs.
struct LocalLLMConfig {
    let provider: AgentProvider
    var endpoint: String
    var modelName: String
    var apiKey: String
    var temperature: Float
    var maxTokens: Int

    private static let defaults = UserDefaults.standard

    /// Load configuration from UserDefaults, with sensible defaults.
    static func load(for provider: AgentProvider) -> LocalLLMConfig {
        let prefix = provider.rawValue
        return LocalLLMConfig(
            provider: provider,
            endpoint:   defaults.string(forKey: "\(prefix)_endpoint") ?? defaultEndpoint(for: provider),
            modelName:  defaults.string(forKey: "\(prefix)_model") ?? defaultModel(for: provider),
            apiKey:     defaults.string(forKey: "\(prefix)_apikey") ?? "",
            temperature: Float(defaults.double(forKey: "\(prefix)_temperature")) == 0 ? 0.7 : Float(defaults.double(forKey: "\(prefix)_temperature")),
            maxTokens:  defaults.integer(forKey: "\(prefix)_maxTokens") == 0 ? 2048 : defaults.integer(forKey: "\(prefix)_maxTokens")
        )
    }

    /// Persist configuration to UserDefaults.
    mutating func save() {
        let prefix = provider.rawValue
        let defaults = UserDefaults.standard
        defaults.set(endpoint, forKey: "\(prefix)_endpoint")
        defaults.set(modelName, forKey: "\(prefix)_model")
        defaults.set(apiKey, forKey: "\(prefix)_apikey")
        defaults.set(Double(temperature), forKey: "\(prefix)_temperature")
        defaults.set(maxTokens, forKey: "\(prefix)_maxTokens")
    }

    private static func defaultEndpoint(for provider: AgentProvider) -> String {
        switch provider {
        case .localOllama: return "http://localhost:11434"
        case .localVllm:   return "http://localhost:8000"
        case .localLlama:  return "http://localhost:8080"
        default:           return "http://localhost:8000"
        }
    }

    private static func defaultModel(for provider: AgentProvider) -> String {
        switch provider {
        case .localOllama: return "llama2"
        case .localVllm:   return "meta-llama/Llama-2-7b-hf"
        case .localLlama:  return "default"
        default:           return "default"
        }
    }
}

// MARK: - Title Format

enum TitleFormat {
    case uppercase       // "CLAUDE"
    case lowercaseTilde  // "claude ~"
    case capitalized     // "Claude"
}

// MARK: - Message

struct AgentMessage {
    enum Role { case user, assistant, error, toolUse, toolResult }
    let role: Role
    let text: String
}

// MARK: - Session Protocol

protocol AgentSession: AnyObject {
    var isRunning: Bool { get }
    var isBusy: Bool { get }
    var history: [AgentMessage] { get set }

    var onText: ((String) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onToolUse: ((String, [String: Any]) -> Void)? { get set }
    var onToolResult: ((String, Bool) -> Void)? { get set }
    var onSessionReady: (() -> Void)? { get set }
    var onTurnComplete: (() -> Void)? { get set }
    var onProcessExit: (() -> Void)? { get set }

    func start()
    func send(message: String)
    func terminate()
}
