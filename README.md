# lil agents

![lil agents](hero-thumbnail.png)

Tiny AI companions that live on your macOS dock.

**Bruce** and **Jazz** walk back and forth above your dock. Click one to open an AI terminal. They walk, they think, they vibe.

Supports **Claude Code**, **OpenAI Codex**, and **GitHub Copilot** CLIs — switch between them from the menubar.

## features

- Animated characters rendered from transparent HEVC video
- Click a character to chat with AI in a themed popover terminal
- Choose Claude, Codex, or Copilot per character (Bruce and Jazz) from the menubar
- Four visual themes: Peach, Midnight, Cloud, Moss
- Thinking bubbles with playful phrases while your agent works
- Sound effects on completion
- First-run onboarding with a friendly welcome
- Auto-updates via Sparkle

## requirements

- macOS Sonoma (14.0+)
- At least one supported CLI installed:
  - [Claude Code](https://claude.ai/download)
  - [OpenAI Codex](https://github.com/openai/codex) — `npm install -g @openai/codex`
  - [GitHub Copilot](https://github.com/github/copilot-cli) — `brew install copilot-cli`

## building

Open `lil-agents.xcodeproj` in Xcode and hit run.

## privacy

lil agents runs entirely on your Mac and sends no personal data anywhere.

- **Your data stays local.** The app plays bundled animations and calculates your dock size to position the characters. No project data, file paths, or personal information is collected or transmitted.
- **AI providers.** Conversations are handled entirely by the CLI process you choose (Claude, Codex, or Copilot) running locally. lil agents does not intercept, store, or transmit your chat content. Any data sent to the provider is governed by their respective terms and privacy policies.
- **No accounts.** No login, no user database, no analytics in the app.
- **Updates.** lil agents uses Sparkle to check for updates, which sends your app version and macOS version. Nothing else.

## license

MIT License. See [LICENSE](LICENSE) for details.
