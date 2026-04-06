import AppKit
import CryptoKit
import Foundation

// MARK: - OpenClaw Device Identity (Ed25519)

/// Generates and persists an Ed25519 keypair for OpenClaw gateway authentication.
/// The device ID is the SHA-256 hex fingerprint of the raw public key bytes,
/// matching the derivation used by the OpenClaw Node.js gateway.
private struct DeviceIdentity {
    let deviceId: String
    let privateKey: Curve25519.Signing.PrivateKey
    let publicKey: Curve25519.Signing.PublicKey

    var publicKeyBase64Url: String {
        base64UrlEncode(publicKey.rawRepresentation)
    }

    func sign(_ payload: String) -> String {
        let signature = try! privateKey.signature(for: Data(payload.utf8))
        return base64UrlEncode(signature)
    }

    /// Builds the auth payload string matching OpenClaw's `buildDeviceAuthPayload` format.
    func authPayload(
        clientId: String, clientMode: String, role: String,
        scopes: [String], signedAtMs: Int64, token: String, nonce: String?
    ) -> String {
        let version = nonce != nil ? "v2" : "v1"
        var parts = [version, deviceId, clientId, clientMode, role,
                     scopes.joined(separator: ","), String(signedAtMs), token]
        if version == "v2" { parts.append(nonce ?? "") }
        return parts.joined(separator: "|")
    }

    // MARK: Persistence

    private static let storageKey = "openClawDeviceIdentity"

    static func loadOrCreate() -> DeviceIdentity {
        if let stored = UserDefaults.standard.data(forKey: storageKey),
           let json = try? JSONSerialization.jsonObject(with: stored) as? [String: String],
           let raw = json["privateKey"], let data = Data(base64Encoded: raw),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            return DeviceIdentity(deviceId: sha256Hex(key.publicKey.rawRepresentation),
                                  privateKey: key, publicKey: key.publicKey)
        }
        let key = Curve25519.Signing.PrivateKey()
        let id = sha256Hex(key.publicKey.rawRepresentation)
        if let data = try? JSONSerialization.data(withJSONObject: [
            "privateKey": key.rawRepresentation.base64EncodedString()
        ]) { UserDefaults.standard.set(data, forKey: storageKey) }
        return DeviceIdentity(deviceId: id, privateKey: key, publicKey: key.publicKey)
    }

    // MARK: Helpers

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - OpenClaw Configuration

/// Gateway connection settings.  Reads from UserDefaults with environment
/// variable fallbacks so the app works out of the box for local gateways
/// and can be reconfigured via the menu bar for remote setups.
struct OpenClawConfig {
    var gatewayURL: String
    var authToken: String
    var sessionKeyPrefix: String
    var agentId: String?

    private static let defaults = UserDefaults.standard

    static func load() -> OpenClawConfig {
        var config = OpenClawConfig(
            gatewayURL:       defaults.string(forKey: "openClawGatewayURL") ?? "ws://localhost:3001",
            authToken:        defaults.string(forKey: "openClawAuthToken") ?? "",
            sessionKeyPrefix: defaults.string(forKey: "openClawSessionPrefix") ?? "lil-agents",
            agentId:          defaults.string(forKey: "openClawAgentId")
        )
        // Environment variable fallbacks
        let env = ProcessInfo.processInfo.environment
        if config.gatewayURL == "ws://localhost:3001" {
            config.gatewayURL = env["OPENCLAW_GATEWAY_URL"]
                             ?? env["CLAWDBOT_GATEWAY_URL"]
                             ?? config.gatewayURL
        }
        if config.authToken.isEmpty {
            config.authToken = env["OPENCLAW_GATEWAY_TOKEN"]
                            ?? env["CLAWDBOT_GATEWAY_TOKEN"]
                            ?? ""
        }
        return config
    }

    func save() {
        let d = Self.defaults
        d.set(gatewayURL, forKey: "openClawGatewayURL")
        d.set(authToken, forKey: "openClawAuthToken")
        d.set(sessionKeyPrefix, forKey: "openClawSessionPrefix")
        if let agentId { d.set(agentId, forKey: "openClawAgentId") }
        else { d.removeObject(forKey: "openClawAgentId") }
    }
}

// MARK: - OpenClaw Session

/// Connects to an OpenClaw gateway over WebSocket using the gateway's
/// native protocol (v3).  Conforms to `AgentSession` so it slots into
/// the existing provider system alongside Claude, Codex, and Copilot.
class OpenClawSession: AgentSession {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pendingNonce: String?
    private var nextRequestId = 0
    private let config = OpenClawConfig.load()
    private let device = DeviceIdentity.loadOrCreate()
    private lazy var sessionKey = "\(config.sessionKeyPrefix):\(UUID().uuidString.lowercased())"

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

    // MARK: Lifecycle

    func start() {
        guard let url = URL(string: config.gatewayURL) else {
            fail("Invalid gateway URL: \(config.gatewayURL)\n\n\(AgentProvider.openclaw.installInstructions)")
            return
        }
        let session = URLSession(configuration: .default)
        urlSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        isRunning = true
        receiveLoop()
    }

    func send(message: String) {
        guard isRunning else { return }
        isBusy = true
        history.append(AgentMessage(role: .user, text: message))

        var params: [String: Any] = [
            "sessionKey": sessionKey,
            "message": message,
            "idempotencyKey": UUID().uuidString
        ]
        if let agentId = config.agentId { params["agentId"] = agentId }
        sendRequest(method: "chat.send", params: params)
    }

    func terminate() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        isRunning = false
        isBusy = false
        onProcessExit?()
    }

    // MARK: WebSocket Transport

    private func sendRequest(method: String, params: [String: Any]) {
        nextRequestId += 1
        let frame: [String: Any] = [
            "type": "req", "id": "lil-\(nextRequestId)",
            "method": method, "params": params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let json = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(json)) { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.onError?("Send error: \(error.localizedDescription)") }
            }
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                let text: String? = {
                    switch msg {
                    case .string(let s): return s
                    case .data(let d):   return String(data: d, encoding: .utf8)
                    @unknown default:    return nil
                    }
                }()
                if let text { DispatchQueue.main.async { self.handleFrame(text) } }
                self.receiveLoop()
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.isBusy = false
                    self.onError?("Connection lost: \(error.localizedDescription)")
                    self.onProcessExit?()
                }
            }
        }
    }

    // MARK: Frame Dispatch

    private func handleFrame(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        switch json["type"] as? String {
        case "event": handleEvent(json)
        case "res":   handleResponse(json)
        default:      break
        }
    }

    // MARK: Events

    private func handleEvent(_ json: [String: Any]) {
        let payload = json["payload"] as? [String: Any] ?? [:]
        switch json["event"] as? String {
        case "connect.challenge":
            pendingNonce = payload["nonce"] as? String
            sendConnectRequest()
        case "chat":
            handleChatEvent(payload)
        default:
            break
        }
    }

    private func handleChatEvent(_ payload: [String: Any]) {
        switch payload["state"] as? String {
        case "delta":
            guard let content = (payload["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return }
            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String { onText?(text) }
                case "tool_use":
                    let name = block["name"] as? String ?? "Tool"
                    let input = block["input"] as? [String: Any] ?? [:]
                    history.append(AgentMessage(role: .toolUse, text: "\(name): \(toolSummary(name, input))"))
                    onToolUse?(name, input)
                case "tool_result":
                    let isError = block["is_error"] as? Bool ?? false
                    let summary = String((block["text"] as? String ?? "").prefix(80))
                    history.append(AgentMessage(role: .toolResult, text: isError ? "ERROR: \(summary)" : summary))
                    onToolResult?(summary, isError)
                default:
                    break
                }
            }

        case "final":
            isBusy = false
            if let content = (payload["message"] as? [String: Any])?["content"] as? [[String: Any]] {
                let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
                if !text.isEmpty { history.append(AgentMessage(role: .assistant, text: text)) }
            }
            onTurnComplete?()

        case "error":
            isBusy = false
            let msg = payload["errorMessage"] as? String ?? "Chat error"
            fail(msg)
            onTurnComplete?()

        case "aborted":
            isBusy = false
            onTurnComplete?()

        default:
            break
        }
    }

    // MARK: Responses

    private func handleResponse(_ json: [String: Any]) {
        let ok = json["ok"] as? Bool ?? false
        let payload = json["payload"] as? [String: Any] ?? [:]

        if ok && (payload["type"] as? String) == "hello-ok" {
            onSessionReady?()
            return
        }
        if !ok {
            let error = json["error"] as? [String: Any]
            let msg = error?["message"] as? String ?? "Unknown error"
            let code = error?["code"] as? String ?? ""
            if code == "auth_required" || code == "auth_failed" {
                onError?("Authentication failed. Set your gateway token in the OpenClaw settings panel or via OPENCLAW_GATEWAY_TOKEN.\n\n\(msg)")
            } else {
                onError?("Gateway error: \(msg)")
            }
        }
    }

    // MARK: Connect Handshake

    private func sendConnectRequest() {
        let role = "operator"
        let scopes = ["operator.read", "operator.write"]
        let signedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

        let payload = device.authPayload(
            clientId: "cli", clientMode: "cli", role: role,
            scopes: scopes, signedAtMs: signedAtMs,
            token: config.authToken, nonce: pendingNonce)
        let signature = device.sign(payload)

        var params: [String: Any] = [
            "minProtocol": 3, "maxProtocol": 3,
            "client": ["id": "cli", "version": "1.0.0",
                       "platform": "macos", "mode": "cli"] as [String: Any],
            "role": role, "scopes": scopes,
            "device": {
                var d: [String: Any] = [
                    "id": device.deviceId,
                    "publicKey": device.publicKeyBase64Url,
                    "signature": signature,
                    "signedAt": signedAtMs
                ]
                if let nonce = pendingNonce { d["nonce"] = nonce }
                return d
            }()
        ]
        if !config.authToken.isEmpty { params["auth"] = ["token": config.authToken] }
        sendRequest(method: "connect", params: params)
    }

    // MARK: Helpers

    private func fail(_ msg: String) {
        onError?(msg)
        history.append(AgentMessage(role: .error, text: msg))
    }

    private func toolSummary(_ name: String, _ input: [String: Any]) -> String {
        switch name {
        case "Bash":        return input["command"] as? String ?? ""
        case "Read":        return input["file_path"] as? String ?? ""
        case "Edit", "Write": return input["file_path"] as? String ?? ""
        case "Glob":        return input["pattern"] as? String ?? ""
        case "Grep":        return input["pattern"] as? String ?? ""
        default:            return input["description"] as? String ?? input.keys.sorted().prefix(3).joined(separator: ", ")
        }
    }

    // MARK: Settings UI

    /// Presents the OpenClaw connection settings panel.
    static func showSettingsPanel(onSave: (() -> Void)? = nil) {
        let config = OpenClawConfig.load()
        let alert = NSAlert()
        alert.messageText = "OpenClaw Connection"
        alert.informativeText = "Connect lil agents to your OpenClaw gateway. You can find these details in your OpenClaw dashboard or from your server administrator."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 220))

        func addRow(_ label: String, value: String, placeholder: String, tooltip: String, y: CGFloat, secure: Bool = false) -> NSTextField {
            let lbl = NSTextField(labelWithString: label)
            lbl.frame = NSRect(x: 0, y: y + 2, width: 115, height: 20)
            lbl.font = .systemFont(ofSize: 13)
            lbl.toolTip = tooltip
            container.addSubview(lbl)
            let field = secure ? NSSecureTextField(frame: .zero) : NSTextField(frame: .zero)
            field.frame = NSRect(x: 120, y: y, width: 275, height: 24)
            field.stringValue = value
            field.placeholderString = placeholder
            field.toolTip = tooltip
            container.addSubview(field)
            return field
        }

        let urlField    = addRow("Server Address:", value: config.gatewayURL, placeholder: "ws://localhost:3001",
                                 tooltip: "The WebSocket URL of your OpenClaw gateway (e.g. ws://localhost:3001 or wss://gateway.example.com).", y: 188)
        let tokenField  = addRow("Auth Token:", value: config.authToken, placeholder: "Paste your token here",
                                 tooltip: "The authentication token for your gateway. You can also set this via the OPENCLAW_GATEWAY_TOKEN environment variable.", y: 148, secure: true)
        let prefixField = addRow("Session Prefix:", value: config.sessionKeyPrefix, placeholder: "lil-agents",
                                 tooltip: "A label used to group your conversations on the server. Each character gets its own session within this prefix.", y: 108)
        let agentField  = addRow("Agent ID:", value: config.agentId ?? "", placeholder: "Optional",
                                 tooltip: "Route messages to a specific agent on the gateway (e.g. \"coder\" or \"writer\"). Leave blank to use the server default.", y: 68)

        // Hint text at the bottom
        let hint = NSTextField(wrappingLabelWithString: "Tip: You can also configure the server address and token using the OPENCLAW_GATEWAY_URL and OPENCLAW_GATEWAY_TOKEN environment variables.")
        hint.frame = NSRect(x: 0, y: 0, width: 400, height: 52)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        container.addSubview(hint)

        alert.accessoryView = container

        if alert.runModal() == .alertFirstButtonReturn {
            var c = OpenClawConfig(
                gatewayURL: urlField.stringValue.isEmpty ? "ws://localhost:3001" : urlField.stringValue,
                authToken: tokenField.stringValue,
                sessionKeyPrefix: prefixField.stringValue.isEmpty ? "lil-agents" : prefixField.stringValue,
                agentId: agentField.stringValue.isEmpty ? nil : agentField.stringValue
            )
            c.save()
            onSave?()
        }
    }
}
