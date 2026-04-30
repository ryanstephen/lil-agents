import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device LLM session using Apple FoundationModels (macOS 26+).
/// Adapts the FoundationModels streaming API to the lil-agents
/// callback-based AgentSession protocol.
@available(macOS 26.0, *)
class FoundationModelsSession: AgentSession {
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

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    private var currentTask: Task<Void, Never>?

    // MARK: - Availability

    static func isAvailable() -> Bool {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default: return false
        }
        #else
        return false
        #endif
    }

    // MARK: - AgentSession

    func start() {
        guard !isRunning else { return }

        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            let s = LanguageModelSession()
            s.prewarm()
            session = s
            isRunning = true
            onSessionReady?()
        default:
            let msg = AgentProvider.foundationModels.installInstructions
            onError?(msg)
            history.append(AgentMessage(role: .error, text: msg))
        }
        #else
        let msg = "FoundationModels framework not available on this system."
        onError?(msg)
        history.append(AgentMessage(role: .error, text: msg))
        #endif
    }

    func send(message: String) {
        guard isRunning else { return }
        guard !isBusy else { return }

        isBusy = true
        history.append(AgentMessage(role: .user, text: message))

        #if canImport(FoundationModels)
        guard let session = session else {
            isBusy = false
            onError?("On-device session is not available.")
            return
        }

        currentTask = Task { [weak self] in
            await self?.streamResponse(session: session, prompt: message)
        }
        #else
        isBusy = false
        onError?("FoundationModels framework not available.")
        #endif
    }

    func terminate() {
        currentTask?.cancel()
        currentTask = nil
        #if canImport(FoundationModels)
        session = nil
        #endif
        isRunning = false
        isBusy = false
        onProcessExit?()
    }

    // MARK: - Streaming

    #if canImport(FoundationModels)
    @MainActor
    private func streamResponse(session: LanguageModelSession, prompt: String) async {
        var accumulated = ""
        do {
            let stream = session.streamResponse(to: prompt)
            for try await snapshot in stream {
                guard !Task.isCancelled else {
                    isBusy = false
                    onTurnComplete?()
                    return
                }
                let full = snapshot.content
                let delta = String(full.dropFirst(accumulated.count))
                if !delta.isEmpty {
                    onText?(delta)
                }
                accumulated = full
            }
            // Stream completed successfully
            if !accumulated.isEmpty {
                history.append(AgentMessage(role: .assistant, text: accumulated))
            }
            isBusy = false
            onTurnComplete?()
        } catch {
            isBusy = false
            onError?(error.localizedDescription)
        }
    }
    #endif

    // MARK: - Context Reset

    /// Recreate the inner LanguageModelSession for /clear support.
    /// The outer session object (and its callback wiring) stays alive.
    func resetContext() {
        currentTask?.cancel()
        currentTask = nil
        #if canImport(FoundationModels)
        let s = LanguageModelSession()
        s.prewarm()
        session = s
        #endif
    }
}
