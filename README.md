# lil agents

![lil agents](hero-thumbnail.png)

Tiny AI companions that live on your macOS dock.

**Bruce** and **Jazz** walk back and forth above your dock. Click one to open an AI terminal. They walk, they think, they vibe.

Supports **Claude Code**, **OpenAI Codex**, **GitHub Copilot**, and **Google Gemini** CLIs — switch between them from the menubar.

**[Download for macOS](https://lilagents.xyz)** · [Website](https://lilagents.xyz)

## features

- Animated characters rendered from transparent HEVC video
- Click a character to chat with AI in a themed popover terminal
- **Live Session mode** — connect to a running Claude Code session and watch tool calls stream in real time
- Switch between Claude, Codex, Copilot, Gemini, and Live Session from the menubar
- Four visual themes: Peach, Midnight, Cloud, Moss
- Slash commands: `/clear`, `/copy`, `/sessions`, `/help` in the chat input
- Copy last response button in the title bar
- Thinking bubbles with playful phrases while your agent works
- Characters roam the full screen and occasionally jump
- Sound effects on completion
- First-run onboarding with a friendly welcome
- Auto-updates via Sparkle

## requirements

- macOS Sonoma (14.0+) — including Sequoia (15.x)
- **Universal binary** — runs natively on both Apple Silicon and Intel Macs
- At least one supported CLI installed:
  - [Claude Code](https://claude.ai/download) — `curl -fsSL https://claude.ai/install.sh | sh`
  - [OpenAI Codex](https://github.com/openai/codex) — `npm install -g @openai/codex`
  - [GitHub Copilot](https://github.com/github/copilot-cli) — `brew install copilot-cli`
  - [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) — `npm install -g @google/gemini-cli`

## live session mode

Live Session lets Bruce and Jazz observe a real Claude Code session — they'll show tool calls, file reads, and edits as they happen, and you can send notes back into the session.

### setup

**1. Copy the bridge hook:**

```bash
mkdir -p ~/.claude/lil-agents
cp hooks/lil-agents-bridge.mjs ~/.claude/lil-agents/bridge.mjs
```

**2. Add hook entries to `~/.claude/settings.json`:**

Add these to the `"hooks"` object in your Claude Code settings (create the `"hooks"` key if it doesn't exist):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "node ~/.claude/lil-agents/bridge.mjs"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "node ~/.claude/lil-agents/bridge.mjs"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "node ~/.claude/lil-agents/bridge.mjs"
          }
        ]
      }
    ]
  }
}
```

If you already have hooks configured, merge these entries into the existing arrays.

**3. Connect:**

- Start any Claude Code session (terminal, VS Code, etc.)
- In the lil agents menubar: **Provider > Live Session** — you'll see your active sessions listed
- Click a session to connect, then click Bruce or Jazz to watch it live

### how it works

```
Your Claude Code session
  │ bridge hook fires on every tool use
  ↓
~/.claude/lil-agents/sessions/<id>.jsonl   (event stream)
~/.claude/lil-agents/sessions/<id>.meta    (session metadata)
  │ Bruce/Jazz watch the file for changes
  ↓
Popover shows live tool calls, results, and notifications
  │ you type a message in the popover
  ↓
~/.claude/lil-agents/inbox/<id>.jsonl      (queued message)
  │ hook reads inbox on next tool use
  ↓
Injected as additionalContext into your Claude session
```

Each character can connect to a different session — put Bruce on one project and Jazz on another.

## install from source

```bash
git clone https://github.com/Orbasker/lil-agents.git
cd lil-agents
git checkout feat/live-session-bridge
xcodebuild -scheme LilAgents -configuration Release build
cp -R ~/Library/Developer/Xcode/DerivedData/lil-agents-*/Build/Products/Release/lil\ agents.app /Applications/
open "/Applications/lil agents.app"
```

Requires Xcode (or Xcode Command Line Tools with full Xcode installed). On first launch you may need to right-click > Open since the app is not notarized.

## privacy

lil agents runs entirely on your Mac and sends no personal data anywhere.

- **Your data stays local.** The app plays bundled animations and calculates your dock size to position the characters. No project data, file paths, or personal information is collected or transmitted.
- **AI providers.** Conversations are handled entirely by the CLI process you choose (Claude, Codex, Copilot, or Gemini) running locally. lil agents does not intercept, store, or transmit your chat content. Any data sent to the provider is governed by their respective terms and privacy policies.
- **No accounts.** No login, no user database, no analytics in the app.
- **Updates.** lil agents uses Sparkle to check for updates, which sends your app version and macOS version. Nothing else.

## license

MIT License. See [LICENSE](LICENSE) for details.
