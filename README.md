# Danae

A zero-config AI-native ops console with a friendly launch command: `danae`.

## What it does

Danae is designed so the user should not have to manually install runtimes first.

- **Windows:** run `Danae.ps1`
- **Linux / macOS:** run `./install.sh`, then launch with `danae`

It will:
- Install missing base utilities like `git`, `curl`, archive support, and `python3` when it can
- Install Ollama if missing
- Configure and start a local Ollama tool proxy if one is not already running
- Provision the runtime it needs automatically
- Install the wrapper dependencies
- Brand the shell for Danae / Istation-style usage
- Create a friendly launch command for non-technical users
- Launch a terminal-first AI ops console

## What the AI knows

Built around an AI-Native Sales Ops framework:
- **Analyze** — review data before humans touch it
- **Recommend** — propose next actions from pipeline signals
- **Automate** — eliminate repetitive CRM and order tasks

Specialized in Salesforce order processing, CRM hygiene, stuck order detection, and weekly data integrity.

## Requirements

- Internet connection on first run
- Linux currently has the strongest auto-install path
- No manual Node.js install required for the Unix installer

## Usage

### Linux / macOS

```bash
chmod +x install.sh Danae.sh
./install.sh
danae
```

On later launches, `danae` will also try to bring Ollama and the local tool proxy back up automatically if they are not already running.

### Windows

Paste this directly into PowerShell:

```powershell
irm https://axismundi.fun/danae.ps1 | iex
```

or download and run `Danae.ps1`.

```
Right-click Danae.ps1 → Run with PowerShell
```

Everything else should be automatic.

---

*Named for Danae — visited by gold.*
