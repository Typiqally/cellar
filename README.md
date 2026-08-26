# Cellar

Cellar is a small native macOS tool that identifies Homebrew packages you may no longer need. It records package identity and time—not command text or arguments—and never removes anything itself.

It is deliberately conservative. A formula or cask is only shown as a removal candidate after the configured observation window when Cellar has a useful usage signal and Homebrew says the package was requested directly, is not depended on, is not pinned, and is not running as a service.

## Requirements

- macOS 14 Sonoma or newer
- Homebrew
- zsh for automatic command-line usage tracking

## Install

Once the tap is published:

```sh
brew install Typiqally/cellar/cellar
cellar setup
```

Then add the line printed by setup to `~/.zshrc`:

```sh
eval "$(cellar init zsh)"
```

The shell hook is opt-in and performs no per-command subprocess. `cellar setup` starts a Homebrew service that wakes periodically, refreshes the inventory, consumes pending events, and exits. There is no resident daemon.

### Install with an AI coding agent

Copy this prompt into an AI agent that can use your terminal:

```text
Install and configure Cellar from https://github.com/Typiqally/cellar on this Mac.

1. Verify that this is macOS 14 or newer and that Homebrew and zsh are available.
2. Run `brew install Typiqally/cellar/cellar`. If Cellar is already installed, leave it installed and continue.
3. Run `cellar setup` to initialize its private local state and scheduled Homebrew service.
4. Add the following line to ~/.zshrc only if an equivalent Cellar initialization is not already present. Preserve every other line and setting in the file:
   `command -v cellar >/dev/null 2>&1 && eval "$(cellar init zsh)"`
5. Verify the result with `cellar doctor`, `cellar status`, `brew services list`, and a fresh zsh process that confirms `_cellar_preexec` is loaded.
6. Report what changed, the number of tracked packages, and the service status.

Do not use sudo, import shell history, uninstall any package, execute a removal recommendation, or modify unrelated shell configuration. Cellar's scheduled service normally exits between runs, so a Homebrew status of `scheduled` is healthy and does not require a resident process.
```

To build the current checkout instead:

```sh
swift build -c release
.build/release/cellar setup --no-service
```

## Use

The default stale window is 90 days:

```sh
cellar report
cellar report --all
cellar report --formulae
cellar report --casks
cellar report --json
cellar explain ripgrep
```

Reports contain advisory `brew uninstall` commands for review and copying. Cellar never executes them. Homebrew's own unused dependency view is also available:

```sh
cellar report --orphans
```

The first interactive shell of the day can print a one-line reminder when candidates exist. Configure the few policy values that materially affect behavior:

```sh
cellar config
cellar config set stale-days 120
cellar config set notice daily     # daily, changed, always, or off
cellar config reset stale-days
```

Protect packages you intend to keep:

```sh
cellar ignore ffmpeg
cellar ignore --list
cellar unignore ffmpeg
```

History import is optional and only extracts timestamped package ownership evidence. It does not store command lines:

```sh
cellar setup --bootstrap-history
cellar setup --history-file ~/.zsh_history
```

## What Cellar observes

- Formulae: commands whose resolved executable lives in Homebrew's `Cellar` and formulae that actually expose an executable in `bin` or `sbin`.
- Casks: Homebrew-owned binaries plus the native Spotlight/Launch Services last-used date of installed app bundles.
- Safety state: requested/dependency status, leaf status, pinning, and active `brew services` entries.

Libraries, fonts, data packages, plugins, GUI apps without useful metadata, and other packages without a supported signal remain `unknown`; they are not removal candidates. “Unused” is evidence to investigate, not proof that removal is safe.

All local state is under `~/Library/Application Support/Cellar` with a private directory and files. Set `CELLAR_STATE_DIR` to override it for testing. No data leaves the Mac.

## Maintenance

```sh
cellar status
cellar refresh
cellar doctor
cellar teardown
cellar teardown --purge --yes
```

`teardown` stops the Homebrew service and preserves state by default. Purging requires both explicit flags. Remove the zsh initialization line yourself when finished.

## Development

```sh
swift test
Scripts/check-coverage.sh
Scripts/package-release.sh 0.1.0 dist
```

The package has no third-party runtime dependencies. It uses Foundation, CoreServices, SQLite from macOS, and direct Homebrew subprocesses without a shell. See [docs/design.md](docs/design.md) for the data flow and safety model.

## License

MIT
