# ask-secret

Native macOS prompts for coding agents that need a credential.

<p align="center"><img src="docs/screenshot.png" alt="ask-secret prompting for a Stripe API key" width="480"></p>

Coding agents regularly need an API key, a token or a sudo password to finish a task. Anything typed into an agent's chat is stored in its transcript and sent to the model provider, so the chat is the wrong place for a credential.

ask-secret gives agents a separate channel. The agent runs one command, a native prompt appears on your Mac, and the value goes straight back to the agent's process. The chat only ever sees that the secret was provided.

## Features

- **Clear requests.** Every prompt shows which agent is asking, the folder it's working in, the reason it gave, and where to find the value.
- **Asked once.** Keys are stored in your login Keychain and reused on later requests.
- **sudo without storing passwords.** The password is passed directly to `sudo`, locally or on a remote host over SSH, and never written anywhere.
- **Works with any agent.** Installs as a skill for Claude Code, Codex, Cursor and the other agents supported by [skills.sh](https://skills.sh).
- **Small and local.** One shell script and one Swift file. No services, no accounts, no network calls of its own.

## Install

```sh
npx skills add theexperiencecompany/ask-secret -g
```

Your agent will use it whenever it needs a credential. To use the command yourself, add it to your PATH:

```sh
~/.claude/skills/ask-secret/bin/ask-secret install
```

The path above is where Claude Code installs skills; other agents use their own skills folder.

Requires macOS 12 or later and Apple's command line tools (`xcode-select --install`). The prompt is compiled on first use.

## Usage

| Command | Description |
| --- | --- |
| `ask-secret get NAME --what TEXT --why TEXT [--where URL]` | Return a stored secret, prompting and storing it if it doesn't exist yet |
| `ask-secret sudo --why TEXT [--on HOST] -- COMMAND` | Prompt for the sudo password and run `COMMAND`, locally or on `HOST` over SSH |
| `ask-secret once --what TEXT --why TEXT [--where URL]` | Prompt for a value without storing it |
| `ask-secret list` | List stored secrets |
| `ask-secret has NAME` | Exit 0 if `NAME` is stored |
| `ask-secret forget NAME` | Delete a stored secret |

```sh
STRIPE_KEY=$(ask-secret get stripe \
  --what "Stripe API key" \
  --why "Set up the webhook for the new checkout flow" \
  --where "https://dashboard.stripe.com/apikeys")

ask-secret sudo --on staging --why "Restart nginx after the config change" -- systemctl restart nginx
```

In the prompt, Return saves, Escape cancels, and Show reveals the value. Unanswered prompts close after 10 minutes. Exit codes are 0 for success, 1 for cancelled and 2 for a usage error.

## Security

Stored secrets live in your login Keychain under `agent/<name>` and can be viewed or removed in Keychain Access.

ask-secret keeps credentials out of chat transcripts, logs and the model provider. It does not limit what an agent does with a value once it has one. Grant agents only the access they need, and prefer short-lived or narrowly scoped keys.

## License

[MIT](LICENSE)
