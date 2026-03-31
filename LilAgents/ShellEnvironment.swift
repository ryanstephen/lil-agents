import Foundation

class ShellEnvironment {
    private static var cachedEnvironment: [String: String]?

    /// Capture the user's login shell environment (zsh -l -i).
    /// Results are cached after the first successful call.
    static func resolve(completion: @escaping ([String: String]?) -> Void) {
        if let cached = cachedEnvironment {
            completion(cached)
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-i", "-c", "echo '---ENV_START---' && env && echo '---ENV_END---'"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        proc.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
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
                    cachedEnvironment = env
                    completion(env)
                } else {
                    completion(nil)
                }
            }
        }
        do { try proc.run() } catch { completion(nil) }
    }

    /// Find a binary by name using the shell PATH + fallback locations.
    static func findBinary(name: String, fallbackPaths: [String], completion: @escaping (String?) -> Void) {
        resolve { env in
            // Check shell PATH first
            if let shellPath = env?["PATH"] {
                for dir in shellPath.components(separatedBy: ":") {
                    let candidate = "\(dir)/\(name)"
                    if FileManager.default.isExecutableFile(atPath: candidate) {
                        completion(candidate)
                        return
                    }
                }
            }

            // Fallback locations
            for fallback in fallbackPaths {
                if FileManager.default.isExecutableFile(atPath: fallback) {
                    completion(fallback)
                    return
                }
            }

            completion(nil)
        }
    }

    /// Build a process environment dict with essential PATH entries included.
    static func processEnvironment(extraPaths: [String] = []) -> [String: String] {
        var env = cachedEnvironment ?? ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let essentialPaths = [
            "\(home)/.local/bin",
            "\(home)/.local/share/claude/versions",
            "/usr/local/bin",
            "/opt/homebrew/bin"
        ] + extraPaths
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let missingPaths = essentialPaths.filter { !currentPath.contains($0) }
        if !missingPaths.isEmpty {
            env["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
        }
        env["TERM"] = "dumb"
        // Remove Claude Code's session marker so spawned CLIs don't see a
        // nested session and refuse to start.
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        // Remove Qoder's session markers for the same reason.
        env.removeValue(forKey: "QODER_CODE")
        env.removeValue(forKey: "QODER_CODE_ENTRYPOINT")
        return env
    }

}
