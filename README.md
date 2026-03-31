# lil agents

![lil agents](hero-thumbnail.png)

Tiny AI companions that live on your macOS dock.

**Bruce** and **Jazz** walk back and forth above your dock. Click one to open an AI terminal. They walk, they think, they vibe.

Supports **Claude Code**, **OpenAI Codex**, **GitHub Copilot**, **Google Gemini**, and **Qoder** CLIs — switch between them from the menubar.

**[Download for macOS](https://lilagents.xyz)** · [Website](https://lilagents.xyz)

## features

- Animated characters rendered from transparent HEVC video
- Click a character to chat with AI in a themed popover terminal
- Switch between Claude, Codex, Copilot, Gemini, and Qoder from the menubar
- Four visual themes: Peach, Midnight, Cloud, Moss
- Slash commands: `/clear`, `/copy`, `/help` in the chat input
- Copy last response button in the title bar
- Thinking bubbles with playful phrases while your agent works
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
  - [Qoder CLI](https://qoder.com) — `curl -fsSL https://qoder.com/install | bash` or `npm install -g @qoder-ai/qodercli`

## building

### From Xcode
Open `lil-agents.xcodeproj` in Xcode and hit run.

### From command line
```bash
git clone https://github.com/ysonggit/lil-agents.git
cd lil-agents
xcodebuild -project lil-agents.xcodeproj -scheme LilAgents \
  -configuration Release \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build
cp -R ~/Library/Developer/Xcode/DerivedData/lil-agents-*/Build/Products/Release/lil\ agents.app /Applications/
open /Applications/lil\ agents.app
```

### Build a DMG
```bash
mkdir -p /tmp/lil-agents-dmg
cp -R ~/Library/Developer/Xcode/DerivedData/lil-agents-*/Build/Products/Release/lil\ agents.app /tmp/lil-agents-dmg/
ln -sf /Applications /tmp/lil-agents-dmg/Applications
hdiutil create -volname "lil agents" -srcfolder /tmp/lil-agents-dmg -ov -format UDZO lil-agents.dmg
```

## energy efficiency

lil agents is optimized for minimal battery impact on macOS:

- **15fps tick rate** — display link throttled from 60fps to 15fps for window positioning
- **Dock geometry caching** — dock size/position cached with 2s refresh interval instead of per-frame UserDefaults reads
- **Position-aware rendering** — `setFrameOrigin` only called when character position actually changes
- **Throttled bubble updates** — thinking bubble text refreshed at 2fps instead of every frame
- **Lazy window levels** — z-order reassigned only when changed, not every frame

These optimizations reduce CPU wakeups by ~75-99% across the rendering pipeline, keeping energy impact minimal during idle and active use.

## privacy

lil agents runs entirely on your Mac and sends no personal data anywhere.

- **Your data stays local.** The app plays bundled animations and calculates your dock size to position the characters. No project data, file paths, or personal information is collected or transmitted.
- **AI providers.** Conversations are handled entirely by the CLI process you choose (Claude, Codex, Copilot, Gemini, or Qoder) running locally. lil agents does not intercept, store, or transmit your chat content. Any data sent to the provider is governed by their respective terms and privacy policies.
- **No accounts.** No login, no user database, no analytics in the app.
- **Updates.** lil agents uses Sparkle to check for updates, which sends your app version and macOS version. Nothing else.

## license

MIT License. See [LICENSE](LICENSE) for details.
