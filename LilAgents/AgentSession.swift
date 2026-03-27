import Foundation

// MARK: - Provider

enum AgentProvider: String, CaseIterable {
    case claude, codex, copilot

    /// Legacy single-app preference; used as fallback when per-character keys are unset (upgrades).
    private static let legacyDefaultsKey = "selectedProvider"

    private static func keyedDefaultsKey(forVideoName name: String) -> String {
        "selectedProvider.\(name)"
    }

    /// Resolved provider for a character (`walk-bruce-01`, `walk-jazz-01`, …).
    static func stored(forVideoName name: String) -> AgentProvider {
        let k = keyedDefaultsKey(forVideoName: name)
        if let raw = UserDefaults.standard.string(forKey: k),
           let p = AgentProvider(rawValue: raw) {
            return p
        }
        if let raw = UserDefaults.standard.string(forKey: legacyDefaultsKey),
           let p = AgentProvider(rawValue: raw) {
            return p
        }
        return defaultForVideoName(name)
    }

    static func setStored(_ provider: AgentProvider, forVideoName name: String) {
        UserDefaults.standard.set(provider.rawValue, forKey: keyedDefaultsKey(forVideoName: name))
    }

    private static func defaultForVideoName(_ name: String) -> AgentProvider {
        name.contains("jazz") ? .codex : .claude
    }

    var displayName: String {
        switch self {
        case .claude:  return "Claude"
        case .codex:   return "Codex"
        case .copilot: return "Copilot"
        }
    }

    var inputPlaceholder: String {
        "Ask \(displayName)..."
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
        }
    }

    func createSession() -> any AgentSession {
        switch self {
        case .claude:  return ClaudeSession()
        case .codex:   return CodexSession()
        case .copilot: return CopilotSession()
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
    var history: [AgentMessage] { get }

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
