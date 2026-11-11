# ask-secret

Native macOS prompts for coding agents that need a credential.

<p align="center"><img src="docs/screenshot.png" alt="ask-secret prompting for a Stripe API key" width="480"></p>

Coding agents regularly need an API key, a token or a sudo password to finish a task. Anything typed into an agent's chat is stored in its transcript and sent to the model provider, so the chat is the wrong place for a credential.

ask-secret gives agents a separate channel. The agent runs one command, a native prompt appears on your Mac, and the value goes straight back to the agent's process. The chat only ever sees that the secret was provided.

## Features

- **Clear requests.** Every prompt shows which agent is asking, the folder it's working in, the reason it gave, and where to find the value.
- **You choose how long.** Keep a value just this once, for an hour, a day, 30 days, or until you remove it. Expired values delete themselves.
- **Touch ID per secret.** Mark a secret so every agent use needs your fingerprint. One approval covers the next 15 minutes.
- **sudo, locally or over SSH.** The password goes straight to `sudo`, is kept per machine behind Touch ID, and a wrong one is detected and discarded.
- **Locked to ask-secret.** Secrets are stored so only ask-secret can read them without asking. Any other program, including Apple's `security` command, triggers a macOS Keychain prompt.
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
| `ask-secret get NAME --what TEXT --why TEXT [--where URL]` | Return a stored secret, prompting for it if it doesn't exist yet |
| `ask-secret sudo --why TEXT [--on HOST] -- COMMAND` | Run `COMMAND` with sudo, locally or on `HOST` over SSH |
| `ask-secret once --what TEXT --why TEXT [--where URL]` | Prompt for a value without storing it |
| `ask-secret list` | List stored secrets, their expiry and Touch ID setting |
| `ask-secret lock` | End current Touch ID approvals |
| `ask-secret has NAME` | Exit 0 if `NAME` is stored |
| `ask-secret forget NAME` | Delete a stored secret |

```sh
STRIPE_KEY=$(ask-secret get stripe \
  --what "Stripe API key" \
  --why "Set up the webhook for the new checkout flow" \
  --where "https://dashboard.stripe.com/apikeys")

ask-secret sudo --on staging --why "Restart nginx after the config change" -- systemctl restart nginx
```

`get` also accepts `--remember once|1h|1d|30d|forever` and `--touchid` as suggestions. You make the final choice in the prompt.

In the prompt, Return saves, Escape cancels, and Show reveals the value. Unanswered prompts close after 10 minutes. Exit codes are 0 for success, 1 for cancelled and 2 for a usage error.

## Security

Stored secrets live in your login Keychain under `agent/<name>` and can be removed in Keychain Access or with `ask-secret forget`. They are saved by ask-secret's own helper, so macOS lets only that helper read them silently. After ask-secret updates, macOS asks once per secret whether the new version may read it.

Touch ID approval happens in the helper. It isn't Secure Enclave–bound, which would require a signed app, but bypassing it means going through the Keychain prompt above.

ask-secret keeps credentials out of chat transcripts, logs and the model provider. It does not limit what an agent does with a value once it has one. Grant agents only the access they need, and prefer short-lived or narrowly scoped keys.

## License

[MIT](LICENSE)
