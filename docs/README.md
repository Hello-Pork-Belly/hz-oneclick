# Documentation Overview

This docs folder provides reference information for the scripts in this repo.
All example paths use placeholders. Replace them with your own site identifier
(e.g. `your-site`) and domain name (e.g. `abc.yourdomain.com`).
Replace placeholder domains with your real domain.

## Install modes

See [Install modes (Full stack vs Frontend-only)](install-modes.md) for a
quick decision guide, required inputs, and connectivity checks.

## Backup

See [Backups](backup.md) for prerequisites and safety checks before running any
backup workflow.

## Service restarts

See [Service restarts and reloads](restarts.md) for the canonical restart and
reload guidance.

## Permissions

See [File permissions and ownership](permissions.md) for the canonical
ownership and permission guidance.

## Configuration files

See [Configuration file locations](config.md) for how to locate active config
files and common paths with placeholders.

## Troubleshooting

See [Troubleshooting](troubleshooting.md) for common startup failure checks and
fixes.

## Optimize security hardening

See [Optimize security hardening (safe)](optimize-security.md) for the
WordPress hardening tasks, reports, and smoke timeout knobs.

## Upgrade

See [Upgrades](upgrade.md) for the step-by-step upgrade workflow and rollback
guidance.

## Logging locations

See [Logging locations](logging.md) for common log paths and discovery
commands.

## Environment variables

See [Environment variables](env.md) for the supported environment variables,
defaults, and safe setup guidance.

## Supported operating systems

Use one of the supported Linux distributions below before running the install
and management scripts:

- Ubuntu LTS (64-bit)
- Debian stable (64-bit)

If you are on another Linux distribution, provision a supported host or VM
first to avoid compatibility gaps.

## Default install paths (placeholders)

| Purpose | Example path | Notes |
| --- | --- | --- |
| WordPress site root | `/var/www/your-site/html` | Replace `your-site` with your site slug. |
| WordPress vhost base | `/var/www/your-site` | Parent directory that contains `html/`. |
| OpenLiteSpeed install | `/usr/local/lsws` | Default OLS installation directory. |
| Script working dir | `/opt/hz-oneclick` | Example location if you clone locally. |

If you use a custom layout, keep it consistent across scripts and update any
references accordingly.
