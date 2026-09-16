# agent-meter

macOS menu bar extra that shows usage limits for Claude, Codex, Grok, and Devin.

The bar is the highest **used** percent across every quota window it can read. Click it for each provider and the limits that vendor actually returned. No plan names, no emails, no web app.

Your tokens stay on your machine. The only network calls are usage requests to the vendor you already signed into with that CLI.

Not affiliated with Anthropic, OpenAI, xAI, or Cognition.

## Requirements

- macOS 13 or later
- Swift 5.9+ (Xcode or Command Line Tools)
- At least one of: Claude Code, Codex CLI, Grok Build, Devin CLI, already signed in

Install Command Line Tools if `swift` is missing:

```bash
xcode-select --install
```

## Setup

1. Sign in to the agents you care about, using their own CLIs:

   ```bash
   claude          # Claude Code
   codex           # or: codex auth
   grok
   devin
   ```

2. Clone and build:

   ```bash
   git clone https://github.com/tryarcanist/agent-meter.git
   cd agent-meter
   ./scripts/build-app.sh
   open dist/AgentMeter.app
   ```

3. The first launch may ask for Keychain access (Claude stores its token there). Choose **Always Allow**. Run `scripts/make-signing-identity.sh` once before building so `build-app.sh` signs the app with a stable self-signed identity — without it, each rebuild invalidates the grant and the prompt returns.

4. Look at the right side of the menu bar for a percent (or `…` while it loads). Click it.

There is no dock icon. Quit from the menu.

To start at login: **System Settings → General → Login Items** → add `AgentMeter.app`.

## What the number means

The menu bar is `max(used percent)` over every window currently returned.

Example: Claude might report `5h 31%`, `7d 33%`, and `Fable 56%`. The bar shows **56%**. That is the weekly cap for the Fable model family, not “all Claude usage” and not remaining quota.

Open the menu to see each window, used percent, and time until reset.

## JSON (no menu)

```bash
swift run -c release AgentMeter --json
```

## Tests

```bash
swift run ParserProbe
```

## Where the numbers come from

| Provider | Credentials | Endpoint |
| --- | --- | --- |
| Claude | Keychain `Claude Code-credentials` or `~/.claude/.credentials.json` | `GET https://api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` | `GET https://chatgpt.com/backend-api/wham/usage` |
| Grok | `~/.grok/auth.json` | `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` |
| Devin | `~/.local/share/devin/credentials.toml` | Cognition `GetUserStatus` |

Those usage APIs are what the CLIs already call. They can change without notice.

## License

MIT
