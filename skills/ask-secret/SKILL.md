---
name: ask-secret
description: Get an API key, token, password or sudo password from the user through a native macOS pop-up instead of the chat. Use whenever a task needs a credential you don't have or needs sudo. Never ask the user to paste a secret into the chat.
---

# ask-secret

Secrets pasted into a chat end up in transcripts, logs and the model provider's servers. This skill asks the user through a macOS pop-up instead. The pop-up shows which agent is asking, from which folder, and why. Saved secrets live in the user's login Keychain as `agent/NAME`. The user decides in the prompt how long each one is kept and whether every use needs their Touch ID.

Run the CLI from this skill's folder: `bin/ask-secret` (use the full path, e.g. `zsh <this skill's directory>/bin/ask-secret ...`). If `ask-secret` is already on PATH, use that.

## Get a saved secret, or ask for it once

```sh
TOKEN=$(ask-secret get github-token \
  --what "GitHub token" \
  --why "Create the release for v1.2" \
  --where "https://github.com/settings/tokens")
```

- If `agent/github-token` is saved, it prints it. If the user protected it with Touch ID, they're asked to approve first; an approval lasts 15 minutes.
- Otherwise the user gets a pop-up and the value is printed (and saved, if they chose to keep it).
- Always pass `--why`, one plain sentence about this task: it's shown in the pop-up and in the Touch ID prompt. `--what` is required when it has to ask. Add `--where` when you know the page where the user gets the value.
- Optional suggestions the user can override: `--remember once|1h|1d|30d|forever` (default forever) and `--touchid` for anything powerful, like admin keys.
- The pop-up waits up to 10 minutes. Give the command a long timeout.

## Run something with sudo

```sh
ask-secret sudo --why "Install the printer driver" -- installer -pkg driver.pkg -target /
ask-secret sudo --on my-server --why "Restart nginx after the config change" -- systemctl restart nginx
```

The password goes straight into `sudo -S` (over SSH with `--on`) and is never printed. It's kept per machine behind Touch ID unless the user chooses otherwise. A wrong password is detected and discarded; run the command again to re-enter it.

## Other commands

```sh
ask-secret once --what "Wi-Fi password" --why "Join the office network"   # ask, print, save nothing
ask-secret list           # saved secrets, how long they're kept, which need Touch ID
ask-secret lock           # end current Touch ID approvals
ask-secret has NAME       # exit 0 if saved
ask-secret forget NAME    # delete one
```

## Rules

- Always capture values into a variable and use them in the same command. Never echo, log or write them to files in the repo.
- Never ask for a secret in the chat, even if the pop-up fails. Say that it failed and why.
- Exit code 1 means the user cancelled or didn't answer. Stop and tell them; don't retry in a loop.
- When you used a short-lived admin key for a one-off change, tell the user to revoke it, then `ask-secret forget` it.
- Never read `agent/*` items with `security` or other tools: macOS will show the user a Keychain warning. Always go through ask-secret.
- macOS only. The first run builds the pop-up from `helper.swift`, which needs Apple's command line tools (`xcode-select --install`).
