# Upgrades

This guide explains how to upgrade this repo safely. All examples use
placeholders (e.g., `abc.yourdomain.com`, `/opt/hz-oneclick`,
`/var/www/your-site/html`).

## What “upgrade” means here

An upgrade means:

- Updating the local repo to a newer tag or commit.
- Re-running the entry script to apply changes.

It does **not** mean per-module manual updates. Let the entry script apply the
latest logic after you pull a new version.

## Pre-flight checks

Before you upgrade:

- **Back up first.** Follow [Backups](backup.md) and confirm you can restore.
- **Check disk space.** Ensure there is room for logs, downloads, and backups.
  (`df -h` is a quick check.)
- **Record your current version.** Save the current commit or tag so you can
  roll back:
  - `git rev-parse HEAD`
  - `git describe --tags --always`
- **Stop conditions.** Do not proceed if backups are missing, disk space is low,
  or your site is already failing for unrelated reasons.

## Update method A: Git clone working dir

Use this if you cloned the repo (example path: `/opt/hz-oneclick`).

1. `cd /opt/hz-oneclick`
2. `git fetch --all --tags`
3. Confirm the branch or tag you want to run:
   - `git status`
   - `git branch --show-current`
   - `git tag --list | tail -n 5`
4. Checkout or pull the desired version:
   - Latest on a branch: `git pull --ff-only`
   - Specific tag: `git checkout v1.2.3`
5. Re-run the entry script (for example, `sudo ./hz.sh`).

## Update method B: curl-based run

Use this if you run the entry script from a URL.

1. **Download the latest script to a temp location.**
   - `curl -fsSL https://abc.yourdomain.com/hz.sh -o /tmp/hz.sh`
2. **Validate you downloaded what you expect.**
   - Compare checksum or content to your source of truth.
3. **Run from the downloaded file.**
   - `sudo bash /tmp/hz.sh`
4. **Pin to a version when needed.**
   - Use a tag- or commit-specific URL, for example:
     - `https://abc.yourdomain.com/releases/v1.2.3/hz.sh`
     - `https://abc.yourdomain.com/commit/abcd1234/hz.sh`

## Handling config drift safely

Treat configuration and data as long-lived, and generated artifacts as
replaceable.

**Keep or back up before upgrading:**

- Site files: `/var/www/your-site/html`
- Config files and environment overrides (for example, `.env` or
  `/etc/your-site/`)
- Credentials and secrets stored outside the repo

**Regenerate as needed:**

- Temporary files, caches, and build outputs
- Generated service unit files (if the script manages them)

**Tips:**

- Use `git status` to see which tracked files changed locally.
- Copy local overrides to a safe location if you expect them to be overwritten.
- Re-apply your changes after the upgrade if needed.

## Post-upgrade verification checklist

After the upgrade:

- Confirm services are running (`systemctl status your-service`).
- Check the site responds:
  - `curl -I https://abc.yourdomain.com`
- Review logs for errors. See [Logging locations](logging.md).
- If issues appear, check [Troubleshooting](troubleshooting.md) and
  [Service restarts](restarts.md).

## Rollback guidance

If the upgrade fails:

- Return to the previous tag/commit:
  - `git checkout v1.2.2`
- Re-run the entry script from the older version.
- If you use curl-based installs, re-download the pinned script for that tag.

Keep the commit hash or tag you recorded in pre-flight checks so rollback is
fast and explicit.

## Common pitfalls

- **Permissions drift:** service user cannot read/write site directories.
- **Missing dependencies:** packages removed or not installed on the host.
- **Ports blocked:** firewall or security group changes.
- **Wrong version:** accidentally running a different branch or unpinned URL.

For deeper guidance, see [Troubleshooting](troubleshooting.md) and
[Service restarts](restarts.md).
