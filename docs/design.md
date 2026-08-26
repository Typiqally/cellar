# Design

## Goals

Cellar answers a narrow question: which directly requested Homebrew packages have enough evidence of prolonged inactivity to deserve human review? It favors low overhead and false negatives over aggressive cleanup.

## Data flow

```text
zsh preexec ── package + timestamp ──► private append-only event log
                                                   │
Homebrew JSON ── inventory and safety state ───────┤
Spotlight ── cask app last-used dates ─────────────┤
                                                   ▼
                                      periodic native maintenance
                                                   │
                                                   ▼
                                       private SQLite snapshot
                                                   │
                                      threshold + safety blockers
                                                   ▼
                                      advisory report / daily notice
```

The zsh hook performs path lookup and string operations using zsh builtins. It does not spawn Cellar for each command. Homebrew's service scheduler runs `cellar maintain` every six hours; the command refreshes state and exits.

## Candidate policy

A package is a candidate only when all of these are true:

1. Cellar supports a meaningful usage signal for its package type.
2. Homebrew marks it as installed on request.
3. No installed package depends on it.
4. It is not pinned, ignored, or running as a Homebrew service.
5. Its last positive use—or the beginning of Cellar's observation window—has aged past `stale-days`.

The default is 90 days. The supported range is 1–3650 days. Packages without a meaningful signal remain unknown indefinitely.

## Storage

`~/Library/Application Support/Cellar` is mode `0700`. The SQLite database and JSON configuration are mode `0600`. SQLite holds the current and previous inventory, maximum observed usage times, deferred events that arrived before an inventory refresh, notice throttling metadata, and ignored status.

Event lines are tab-delimited and versioned:

```text
1<TAB>unix-seconds<TAB>formula|cask<TAB>package-token
```

Tokens are length-limited and allow only Homebrew token characters. Command text and arguments never cross this boundary.

## Removal boundary

Cellar renders shell-quoted `brew uninstall` commands but never launches them. It does not recursively remove dependencies. `cellar report --orphans` delegates to `brew autoremove --dry-run` so Homebrew remains the authority on dependency cleanup.

## Future work

Endpoint Security could provide broader process execution evidence, but it requires user approval and a system extension entitlement. It is intentionally outside the lightweight first release.
