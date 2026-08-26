# Security

## Reporting

Please report a suspected vulnerability privately through GitHub's security advisory feature for `Typiqally/cellar`. Do not include secrets or private shell history in a public issue.

## Data and trust model

Cellar stores package kind, package token, timestamps, configuration, and derived Homebrew safety state locally. It does not store command text or arguments, use network APIs, or run suggested removal commands.

The zsh hook resolves executable ownership and appends a versioned package-only event. The native process strictly validates events, binds SQLite values as parameters, invokes Homebrew directly without a shell, caps surfaced error output, and keeps its state directory private.

Homebrew inventory and Spotlight metadata are advisory inputs. A compromised local account or Homebrew installation is outside the threat model. Reports should always be reviewed before copying an uninstall command.
