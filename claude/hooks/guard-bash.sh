#!/bin/bash
# coral-safety-kit · guard-bash.sh
# A Claude Code PreToolUse hook for the Bash tool. It reads the command Claude wants to run and:
#   deny  · force push, push to main or master, rm -r -f outside a few build folders,
#           reading production env files, piping a download into a shell
#   ask   · production deploys, destructive SQL, git reset --hard, git clean -f
#   allow · everything else goes on to Claude Code's normal permission check
#
# It matches the command's text, so it is a seatbelt, not a wall: `bash -c "$(...)"`, a script file
# or an alias can get past it. Pair it with deny rules, the sandbox and production keys the agent
# never sees. Needs jq (built into macOS 15 and later; `apt install jq` on Linux).

set -u

# Fail closed: a safety hook that can't read the command must not let it through.
if ! command -v jq >/dev/null 2>&1; then
  echo "coral-safety-kit: jq is not installed, so this command was blocked. Install jq (apt install jq / brew install jq)." >&2
  exit 2
fi
input=$(cat)
if ! cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo "coral-safety-kit: couldn't read the hook input, so this command was blocked." >&2
  exit 2
fi
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Print Claude Code's PreToolUse answer and stop.
decide() {
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

# One line per shell command: split on ; && || | and newlines, so `cd x && rm -rf y` checks both.
segments=$(printf '%s\n' "$cmd" | awk '{ gsub(/&&|\|\||;|\|/, "\n"); print }')

# Folders that are safe to delete because a build or install recreates them.
rebuildable='^(\./)?(node_modules|dist|build|out|\.next|\.turbo|\.cache|coverage|target|tmp|\.pytest_cache|__pycache__)/?$'

# a download piped into a shell (checked on the whole command, since the pipe splits it)
if printf '%s\n' "$cmd" | grep -Eq '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh([[:space:]]|$)'; then
  decide deny "Blocked by coral-safety-kit: piping a download into a shell. Download it, show the user, then run it."
fi

while IFS= read -r seg; do
  seg=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^(sudo|command|exec|env)[[:space:]]+//')
  [ -z "$seg" ] && continue

  # rm with both -r and -f, unless every target is a rebuildable folder
  if printf '%s' "$seg" | grep -Eq '^rm[[:space:]]'; then
    flags=$(printf '%s' "$seg" | grep -Eo '(^|[[:space:]])-[A-Za-z-]+' | tr -d ' \n')
    if printf '%s' "$flags" | grep -Eq '(r|R|--recursive)' && printf '%s' "$flags" | grep -Eq '(f|--force)'; then
      targets=$(printf '%s' "$seg" | tr ' ' '\n' | sed '1d' | grep -Ev '^-')
      [ -z "$targets" ] && decide deny "Blocked by coral-safety-kit: rm -rf with no target."
      while IFS= read -r t; do
        printf '%s' "$t" | grep -Eq "$rebuildable" || decide deny "Blocked by coral-safety-kit: rm -rf $t. Delete files one by one, or ask the user to run it."
      done <<< "$targets"
    fi
  fi

  # git push: never force, never straight to main or master
  if printf '%s' "$seg" | grep -Eq '^git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)'; then
    printf '%s' "$seg" | grep -Eq '[[:space:]](-f|--force|--force-with-lease)([[:space:]=]|$)|[[:space:]]\+[^[:space:]]+' &&
      decide deny "Blocked by coral-safety-kit: force push. Push a new branch and open a pull request."
    printf '%s' "$seg" | grep -Eq '[[:space:]](main|master)([[:space:]]|$)|:(main|master)([[:space:]]|$)' &&
      decide deny "Blocked by coral-safety-kit: push to main or master. Push a branch and open a pull request."
# fsmonitor off, so a hostile repo's git config can't make this check run a program
    branch=$(git -c core.fsmonitor=false -C "${cwd:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
      printf '%s' "$seg" | grep -Eq '^git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]+(-u|--set-upstream))?([[:space:]]+origin)?[[:space:]]*$' &&
        decide deny "Blocked by coral-safety-kit: this push goes to $branch. Create a branch first."
    fi
  fi

  # production env files
  printf '%s' "$seg" | grep -Eq '\.env\.(prod|production)([^[:alnum:]_.-]|$)' &&
    decide deny "Blocked by coral-safety-kit: production env file. Agents work with development keys only."

  # ask first: production deploys and changes that can't be undone
  printf '%s' "$seg" | grep -Eq '^(npx[[:space:]]+)?(vercel|netlify)[[:space:]].*--prod' &&
    decide ask "coral-safety-kit: this deploys to production."
  printf '%s' "$seg" | grep -Eq '^(fly|flyctl)[[:space:]]+deploy|^firebase[[:space:]]+deploy|^(npx[[:space:]]+)?wrangler[[:space:]]+deploy|^terraform[[:space:]]+(apply|destroy)|^pulumi[[:space:]]+(up|destroy)|^kubectl[[:space:]]+(apply|delete|scale|rollout)|^helm[[:space:]]+(install|upgrade|uninstall)' &&
    decide ask "coral-safety-kit: this changes live infrastructure."
  if printf '%s' "$seg" | grep -Eq '^(npx[[:space:]]+)?supabase[[:space:]]+db[[:space:]]+(push|reset)'; then
    printf '%s' "$seg" | grep -Eq -- '--local' || decide ask "coral-safety-kit: this changes a remote Supabase database."
  fi
  printf '%s' "$seg" | grep -Eiq 'drop[[:space:]]+(table|database|schema)|truncate[[:space:]]+(table[[:space:]]+)?[[:alnum:]_]' &&
    decide ask "coral-safety-kit: this SQL deletes data."
  if printf '%s' "$seg" | grep -Eiq 'delete[[:space:]]+from[[:space:]]'; then
    printf '%s' "$seg" | grep -Eiq '[[:space:]]where[[:space:]]' || decide ask "coral-safety-kit: this SQL deletes every row."
  fi
  printf '%s' "$seg" | grep -Eq '^git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*f|checkout[[:space:]]+--[[:space:]]+\.|restore[[:space:]]+\.)' &&
    decide ask "coral-safety-kit: this throws away uncommitted work."
  printf '%s' "$seg" | grep -Eq '^npm[[:space:]]+publish|^(pnpm|yarn)[[:space:]]+publish' &&
    decide ask "coral-safety-kit: this publishes a package."
done <<< "$segments"

exit 0
