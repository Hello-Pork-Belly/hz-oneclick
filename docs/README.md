# Documentation Overview

This docs folder provides reference information for the scripts in this repo.
All example paths use placeholders. Replace them with your own site identifier
(e.g. `your-site`) and domain name (e.g. `abc.yourdomain.com`).
Replace placeholder domains with your real domain.

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

## Upgrade

See [Upgrades](upgrade.md) for the step-by-step upgrade workflow and rollback
guidance.

## Logging locations

See [Logging locations](logging.md) for common log paths and discovery
commands.

## Environment variables

See [Environment variables](env.md) for the supported environment variables,
defaults, and safe setup guidance.

## Default install paths (placeholders)

| Purpose | Example path | Notes |
| --- | --- | --- |
| WordPress site root | `/var/www/your-site/html` | Replace `your-site` with your site slug. |
| WordPress vhost base | `/var/www/your-site` | Parent directory that contains `html/`. |
| OpenLiteSpeed install | `/usr/local/lsws` | Default OLS installation directory. |
| Script working dir | `/opt/hz-oneclick` | Example location if you clone locally. |

If you use a custom layout, keep it consistent across scripts and update any
references accordingly.
