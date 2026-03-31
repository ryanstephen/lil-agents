import Foundation

// MARK: - Provider

enum AgentProvider: String, CaseIterable {
    case claude, codex, copilot, gemini, live

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
        case .claude:  return "Claude"
        case .codex:   return "Codex"
        case .copilot: return "Copilot"
        case .gemini:  return "Gemini"
        case .live:    return "Live Session"
        }
    }

    var inputPlaceholder: String {
        switch self {
        case .live: return "Send a note to the session..."
        default:    return "Ask \(displayName)..."
        }
    }

    /// Returns provider name styled per theme format.
    func titleString(format: TitleFormat) -> String {
        switch format {
        case .uppercase:      return displayName.uppercased()
        case .lowercaseTilde: return "\(displayName.lowercased()) ~"
        case .capitalized:    return displayName
        }
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
        case .live:
            return "To use Live Session, install the bridge hook.\nSee: hooks/lil-agents-bridge.mjs in the project."
        }
    }

    /// Whether this provider requires session selection before use.
    var requiresSessionPicker: Bool {
        self == .live && Self.selectedLiveSession == nil
    }

    /// The currently selected live session (set via menu bar).
    static var selectedLiveSession: LiveSession.DiscoveredSession?

    func createSession() -> any AgentSession {
        switch self {
        case .claude:  return ClaudeSession()
        case .codex:   return CodexSession()
        case .copilot: return CopilotSession()
        case .gemini:  return GeminiSession()
        case .live:    fatalError("Use createLiveSession(sessionId:projectName:) instead")
        }
    }

    func createLiveSession(sessionId: String, projectName: String) -> LiveSession {
        LiveSession(sessionId: sessionId, projectName: projectName)
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
