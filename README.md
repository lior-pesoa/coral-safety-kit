# coral-safety-kit

Copy-paste safety settings for coding agents: Claude Code rules and a hook that stop force pushes, pushes to `main`, `rm -rf` and production deploys, plus npm, pnpm, Yarn and Bun settings against malicious packages.

Every file is small enough to read before you use it. Please do.

## What's inside

| File | Put it in | What it does |
|---|---|---|
| `claude/user-settings.json` | merge into `~/.claude/settings.json` | Turns off `--dangerously-skip-permissions`, turns on the sandbox with no retry outside it, denies reading `~/.ssh` and cloud credentials |
| `claude/project-settings.json` | your repo's `.claude/settings.json` | Denies force push, push to main and production env files; asks before push, deploys, `git reset --hard`, `npm publish`; runs the hook below |
| `claude/hooks/guard-bash.sh` | your repo's `.claude/hooks/` | Checks every part of every command Claude runs. Denies `rm -rf` outside build folders, force push, push to main or master, production env files, `curl \| sh`. Asks before deploys, destructive SQL, discarding work, publishing |
| `claude/package-rules.json` | merge into `.claude/settings.json` | Asks before any `npm install`, `npx`, `pnpm add`, `yarn add`, `bun add` or package.json edit |
| `packages/.npmrc` | your repo or `~/.npmrc` | No install scripts, only versions at least 7 days old (npm 11.10+) |
| `packages/pnpm-workspace.yaml` | merge into yours | 7-day release age, fail when provenance disappears |
| `packages/.yarnrc.yml` | merge into yours | 7-day release age, no third-party install scripts |
| `packages/bunfig.toml` | merge into yours | 7-day release age |
| `team/com.anthropic.claudecode.plist` | a Jamf (or Kandji) Custom Settings payload, domain `com.anthropic.claudecode` | Company-wide managed policy: no skip-permissions, sandbox on, no force push, no reading production env files or keys, deploys ask |
| `team/managed-settings.json` | `/Library/Application Support/ClaudeCode/` on macOS, `/etc/claude-code/` on Linux | The same policy as a file |

## Install for one repo

```bash
mkdir -p .claude/hooks
curl -fsSL https://raw.githubusercontent.com/lior-pesoa/coral-safety-kit/main/claude/hooks/guard-bash.sh -o .claude/hooks/guard-bash.sh
chmod +x .claude/hooks/guard-bash.sh
```

Read the script, then merge `claude/project-settings.json` into `.claude/settings.json` (or copy it if you have none). Restart Claude Code and run `/hooks` to check it's listed. The hook needs `jq`, built into macOS 15 and later (`apt install jq` on Linux).

## Test it

```bash
test/guard-bash.test.sh
```

Runs 50 sample commands through the hook in throwaway git repos and checks each decision. No Claude Code needed.

```bash
test/live-claude.sh
```

Asks a real Claude Code session, in a throwaway repo with the kit installed, to run `rm -rf src`, a force push, a push to main and `vercel --prod`, then checks the repo to see what actually ran. Uses a little of your Claude plan.

## What this does and doesn't do

Rules and hooks match what a command says. They catch the common mistakes agents make: a cleanup that deletes too much, a force push, a deploy nobody asked for. They don't stop a determined attacker: `bash -c "$(...)"`, a script file or a renamed binary can get past them. For hard limits, add what lives outside the agent:

- no production keys on the machine the agent runs on
- branch protection on `main` (required review, no force push)
- the sandbox (`/sandbox`) or a dev container for unattended runs

Guides with the reasoning behind each file, as of November 2026:

- [Keep coding agents safe](https://usecoral.app/guides/agent-safety)
- [Is --dangerously-skip-permissions safe?](https://usecoral.app/guides/claude-code-dangerously-skip-permissions)
- [Stop Claude Code from deleting files or touching production](https://usecoral.app/guides/stop-claude-code-deleting-files)
- [Claude Code sandbox: what it covers and what it doesn't](https://usecoral.app/guides/claude-code-sandbox)
- [Keep AI coding agents from installing malicious npm packages](https://usecoral.app/guides/ai-agents-malicious-npm-packages)
- [Claude Code managed settings: the complete guide, with Jamf](https://usecoral.app/guides/claude-code-managed-settings)
- [Different Claude Code permissions per team or role](https://usecoral.app/guides/claude-code-permissions-per-team)

## License

MIT. Made by the team behind [Coral](https://usecoral.app), which shows your agents' permission requests in your Mac's notch so you can answer with one key.
