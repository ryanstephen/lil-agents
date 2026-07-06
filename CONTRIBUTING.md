# Contributing to lil-agents

Thanks for interest in contributing! Here's how to get started.

## Local LLM Support

This project supports multiple local LLM backends for privacy-first AI interactions.

### Supported Local LLMs

#### Ollama (Recommended for beginners)

Easiest to use with pre-quantized models:

```bash
brew install ollama
ollama serve
```

In another terminal:
```bash
ollama run llama2
```

#### vLLM (High-performance inference)

For faster inference with HuggingFace models:

```bash
python3 -m venv ~/.venv
source ~/.venv/bin/activate
pip install vllm
python -m vllm.entrypoints.openai.api_server
```

#### Llama.cpp (Lightweight)

Minimal resource footprint, great for older machines:

```bash
brew install llama.cpp
llama-cli -m <path-to-model.gguf> -i
```

### Adding a New Local LLM Provider

1. Add a new case to `AgentProvider` enum in `LilAgents/AgentSession.swift`:
   ```swift
   case localMyLLM
   ```

2. Update provider properties:
   ```swift
   var displayName: String {
       switch self {
       case .localMyLLM: return "Local • MyLLM"
       // ...
       }
   }

   var binaryName: String {
       switch self {
       case .localMyLLM: return "myllm"
       // ...
       }
   }
   ```

3. Add installation instructions:
   ```swift
   var installInstructions: String {
       switch self {
       case .localMyLLM:
           return "Installation instructions for MyLLM..."
       // ...
       }
   }
   ```

4. Update factory method:
   ```swift
   func createSession() -> any AgentSession {
       switch self {
       case .localMyLLM: return LocalLLMSession(provider: .localMyLLM)
       // ...
       }
   }
   ```

5. Add binary search paths in `detectAvailableProviders()` if needed

6. Test with your LLM installed locally

## Code Style

- Follow Swift naming conventions (camelCase for variables/functions, PascalCase for types)
- Use `private` for internal properties
- Add `// MARK: -` comments to organize code sections
- Document public functions with comments
- Use descriptive variable names
- Prefer `guard let` for optional unwrapping

## Testing

1. Install a local LLM (Ollama recommended)
2. Build the app in Xcode: `open lil-agents.xcodeproj`
3. Run and select the LLM from Provider menu
4. Test interactive chat

## Building

```bash
open lil-agents.xcodeproj
```

Build with Xcode or via command line:
```bash
xcodebuild -scheme LilAgents -configuration Release
```

## Submitting Changes

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit with clear messages
4. Push and open a PR to `ryanstephen/lil-agents`
5. Reference any related issues
