# lil agents · Merit & Muse fork

Personal fork of **[lil agents](https://github.com/ryanstephen/lil-agents)** — tiny AI companions on the macOS dock. This repo is **built on top of that project**; upstream owns the core app idea, architecture, and baseline features.

**Upstream repository:** [github.com/ryanstephen/lil-agents](https://github.com/ryanstephen/lil-agents)  
**This fork:** custom characters (**Merit** & **Muse**), animation assets, UI experiments, and ongoing work on branches like `fork/wip-all-changes`.

Official downloads and product site for the original app: [lilagents.xyz](https://lilagents.xyz).

## Demo

_Add a link or embed for your demo video here._

## Process

_Notes on how you created the animation, iteration workflow, tools, etc._

## Git remotes & workflow

| Remote | Points to |
| ---------- | --------- |
| `origin`   | **Your fork** (this GitHub repo — push your branches here). |
| `upstream` | **Original repo** — [ryanstephen/lil-agents](https://github.com/ryanstephen/lil-agents). |

If `upstream` is not set yet:

```bash
git remote add upstream https://github.com/ryanstephen/lil-agents.git
git fetch upstream
```

**Keeping up with upstream**

1. `git fetch upstream`
2. Merge or rebase `upstream/main` into a **tracking branch** you keep close to upstream (e.g. local `main`).
3. When you want those changes in your experimental branch, merge (or rebase) that into `fork/wip-all-changes` **when you’re ready**, and resolve conflicts there.

That way `main` (or whatever you use as “clean upstream + minimal fork fixes”) stays easy to compare to `upstream/main`, and WIP stays a sandbox.

## Building

Open `lil-agents.xcodeproj` in Xcode and run the **LilAgents** scheme.

Requirements and provider CLIs match upstream; see the [upstream README](https://github.com/ryanstephen/lil-agents/blob/main/README.md) for CLI install links and privacy notes.

## License

MIT — see [LICENSE](LICENSE) (same license family as upstream; refer to upstream for their exact terms).
