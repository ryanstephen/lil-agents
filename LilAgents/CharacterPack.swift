import AppKit

struct CharacterConfig {
    let videoName: String
    let displayName: String
    let accelStart: CFTimeInterval
    let fullSpeedStart: CFTimeInterval
    let decelStart: CFTimeInterval
    let walkStop: CFTimeInterval
    let walkAmountRange: ClosedRange<CGFloat>
    let yOffset: CGFloat
    let flipXOffset: CGFloat
    let characterColor: NSColor
    let initialPosition: CGFloat
    let initialPauseRange: ClosedRange<Double>
}

struct CharacterPack {
    let id: String
    let name: String
    let characters: [CharacterConfig]
    let thinkingPhrases: [String]
    let completionPhrases: [String]
    let onboardingGreeting: String
    let onboardingWelcome: String

    // MARK: - Presets

    static let `default` = CharacterPack(
        id: "default",
        name: "Bruce & Jazz",
        characters: [
            CharacterConfig(
                videoName: "walk-bruce-01", displayName: "Bruce",
                accelStart: 3.0, fullSpeedStart: 3.75, decelStart: 8.0, walkStop: 8.5,
                walkAmountRange: 0.4...0.65, yOffset: -3, flipXOffset: 0,
                characterColor: NSColor(red: 0.4, green: 0.72, blue: 0.55, alpha: 1.0),
                initialPosition: 0.3, initialPauseRange: 0.5...2.0
            ),
            CharacterConfig(
                videoName: "walk-jazz-01", displayName: "Jazz",
                accelStart: 3.9, fullSpeedStart: 4.5, decelStart: 8.0, walkStop: 8.75,
                walkAmountRange: 0.35...0.6, yOffset: -7, flipXOffset: -9,
                characterColor: NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0),
                initialPosition: 0.7, initialPauseRange: 8.0...14.0
            ),
        ],
        thinkingPhrases: [
            "hmm...", "thinking...", "one sec...", "ok hold on",
            "let me check", "working on it", "almost...", "bear with me",
            "on it!", "gimme a sec", "brb", "processing...",
            "hang tight", "just a moment", "figuring it out",
            "crunching...", "reading...", "looking..."
        ],
        completionPhrases: [
            "done!", "all set!", "ready!", "here you go", "got it!",
            "finished!", "ta-da!", "voila!"
        ],
        onboardingGreeting: "hi!",
        onboardingWelcome: """
        hey! we're bruce and jazz — your lil dock agents.

        click either of us to open a Claude AI chat. we'll walk around while you work and let you know when Claude's thinking.

        check the menu bar icon (top right) for themes, sounds, and more options.

        click anywhere outside to dismiss, then click us again to start chatting.
        """
    )

    static let droids = CharacterPack(
        id: "droids",
        name: "Droids",
        characters: [
            CharacterConfig(
                videoName: "walk-r2d2-01", displayName: "R2-Do2",
                accelStart: 3.0, fullSpeedStart: 3.75, decelStart: 8.0, walkStop: 8.5,
                walkAmountRange: 0.4...0.65, yOffset: 30, flipXOffset: 0,
                characterColor: NSColor(red: 0.2, green: 0.5, blue: 0.85, alpha: 1.0),
                initialPosition: 0.2, initialPauseRange: 0.5...2.0
            ),
            CharacterConfig(
                videoName: "walk-c3po-01", displayName: "C-3POa",
                accelStart: 3.9, fullSpeedStart: 4.5, decelStart: 8.0, walkStop: 8.75,
                walkAmountRange: 0.35...0.6, yOffset: 30, flipXOffset: -9,
                characterColor: NSColor(red: 0.85, green: 0.72, blue: 0.2, alpha: 1.0),
                initialPosition: 0.5, initialPauseRange: 8.0...14.0
            ),
            CharacterConfig(
                videoName: "walk-bb8-01", displayName: "BB-Gr8",
                accelStart: 3.0, fullSpeedStart: 3.75, decelStart: 8.0, walkStop: 8.5,
                walkAmountRange: 0.45...0.7, yOffset: 30, flipXOffset: 0,
                characterColor: NSColor(red: 0.92, green: 0.5, blue: 0.15, alpha: 1.0),
                initialPosition: 0.8, initialPauseRange: 4.0...8.0
            ),
        ],
        thinkingPhrases: [
            "boop beep...", "searching feelings...", "consulting the Force...", "hold on...",
            "recalculating hyperspace...", "scanning...", "almost there...", "patience you must have",
            "on it, master!", "standby...", "computing...", "processing...",
            "stay on target...", "one moment...", "the Force is strong...",
            "beep bwoop...", "accessing archives...", "calculating odds..."
        ],
        completionPhrases: [
            "the Force is with you!", "mission complete!", "ready, master!", "these are the droids!",
            "done it is!", "I have a good feeling!", "roger roger!", "may the Force..."
        ],
        onboardingGreeting: "beep boop!",
        onboardingWelcome: """
        greetings! we're R2-Do2, C-3POa, and BB-Gr8 — your lil dock droids.

        click any of us to open a Claude AI chat. we'll patrol the dock while you work and let you know when the Force is computing.

        check the menu bar icon (top right) for themes, sounds, and more options.

        click anywhere outside to dismiss, then click us again to start chatting. may the Force be with you!
        """
    )

    static let allPacks: [CharacterPack] = [.default, .droids]
    static var current: CharacterPack = .default

    // MARK: - Persistence

    private static let userDefaultsKey = "selectedCharacterPack"

    static func loadSaved() -> CharacterPack {
        let id = UserDefaults.standard.string(forKey: userDefaultsKey) ?? "default"
        return allPacks.first { $0.id == id } ?? .default
    }

    static func saveCurrent() {
        UserDefaults.standard.set(current.id, forKey: userDefaultsKey)
    }
}
