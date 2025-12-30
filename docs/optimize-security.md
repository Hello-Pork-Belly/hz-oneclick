# Optimize security hardening (safe)

This document describes the Optimize security hardening tasks added to the
WordPress installer flow. The UI is bilingual (EN/ZH), but the guidance below
is in English only.

## Where the Optimize tasks live and how to run them

* Source: `modules/wp/install-ols-wp-standard.sh`.
* Entry point: run `hz.sh` and choose **Optimize (post-install)**, then select
  the security hardening items from the **Optimize Menu**.
* Non-interactive rerun: `HZ_PHASE=optimize` (the script prints the exact
  rerun command after install).

## Security hardening tasks (Optimize menu)

The tasks below are safe to re-run. All write operations use HZ-ONECLICK
markers in `.htaccess` blocks (or check for existing constants) to make them
idempotent.

### Read-only checks

1) **Security snapshot** (`Optimize: Security snapshot`)
   * High-level: collects a WordPress security snapshot (version, URLs,
     permalink structure, registration flags, admin users, permissions
     snapshot, and presence checks).
   * Files touched: none (read-only).
   * Report: `/tmp/hz-wp-security-snapshot.txt`.
   * Requires wp-cli and a WordPress install.

2) **Hardening check** (`Optimize: Hardening check`)
   * High-level: inspects `wp-config.php` permissions, common constants
     (e.g., `DISALLOW_FILE_EDIT`), and finds world-writable paths.
   * Files touched: none (read-only).
   * Report: `/tmp/hz-wp-hardening-check.txt`.
   * Requires wp-cli and a WordPress install.

### Safe hardening actions

3) **wp-config hardening (safe)**
   * High-level: ensures `DISALLOW_FILE_EDIT` is set in `wp-config.php`.
   * Files touched: `wp-config.php`.
   * Backup/rollback: creates `wp-config.php.bak-YYYYmmdd-HHMMSS` alongside the
     original file and restores it if the update fails.
   * Report: `/tmp/hz-wp-config-hardening.txt`.
   * Requires wp-cli and a WordPress install.

4) **Filesystem permissions hardening (safe)**
   * High-level: removes the other-writable bit from files under the site root
     and enforces `600` on `wp-config.php`.
   * Files touched: site root paths with other-writable permissions, plus
     `wp-config.php` if present.
   * Backup/rollback: no file copies; permissions are updated in place. The
     report records what changed.
   * Report: `/tmp/hz-wp-permissions-hardening.txt`.
   * Requires wp-cli and a WordPress install.

5) **Sensitive files web access block (safe)**
   * High-level: blocks web access to sensitive files like `wp-config.php`,
     `.env`, and lockfiles using a `.htaccess` block.
   * Files touched: site root `.htaccess` (created if missing).
   * Markers: `# BEGIN HZ SENSITIVE FILES BLOCK` / `# END HZ SENSITIVE FILES BLOCK`.
   * Backup/rollback: creates `/tmp/hz-htaccess-backup-YYYYmmdd-HHMMSS.bak` when
     an existing `.htaccess` is present and restores it if validation fails.
   * Report: `/tmp/hz-wp-sensitive-files-block.txt`.
   * No wp-cli required.

6) **XML-RPC block (safe)**
   * High-level: blocks `xmlrpc.php` via a `.htaccess` `<Files>` rule.
   * Files touched: site root `.htaccess` (must exist).
   * Markers: `# BEGIN HZ-ONECLICK XMLRPC BLOCK` / `# END HZ-ONECLICK XMLRPC BLOCK`.
   * Backup/rollback: creates `.htaccess.bak.YYYYmmdd-HHMMSS` in the site root and
     restores it if validation fails.
   * Report: `/tmp/hz-wp-xmlrpc-block.txt`.
   * No wp-cli required.

7) **Directory listing block (safe)**
   * High-level: inserts `Options -Indexes` in `.htaccess` to disable directory
     listing.
   * Files touched: site root `.htaccess` (created if missing).
   * Markers: `# HZ-ONECLICK: directory listing block (safe) BEGIN` / `END`.
   * Backup/rollback: creates `/tmp/hz-wp-htaccess-dirlist-backup.YYYYmmdd-HHMMSS`
     (empty placeholder if `.htaccess` was missing) and restores it if
     validation fails.
   * Report: `/tmp/hz-wp-dirlisting-block.txt`.
   * No wp-cli required.

8) **Uploads PHP execution block (safe)**
   * High-level: blocks PHP execution inside `wp-content/uploads`.
   * Files touched: `wp-content/uploads/.htaccess`.
   * Markers: `# BEGIN HZ UPLOADS PHP BLOCK` / `# END HZ UPLOADS PHP BLOCK`.
   * Backup/rollback: creates `/tmp/hz-uploads-htaccess.bak.YYYYmmdd-HHMMSS` and
     restores it if validation fails.
   * Report: `/tmp/hz-wp-uploads-php-block.txt`.
   * No wp-cli required.

## Security hardening suite (safe)

The **Security hardening suite (safe)** runs a subset of the tasks above in
order and records a consolidated summary report.

Order:
1) Security snapshot
2) Hardening check
3) wp-config hardening (safe)
4) Filesystem permissions hardening (safe)
5) XML-RPC block (safe)
6) Uploads PHP execution block (safe)
7) Sensitive files web access block (safe)
8) Directory listing block (safe)

Skip behavior:
* Tasks that require wp-cli are skipped if wp-cli is missing or WordPress is
  not installed yet.
* Tasks that do not require wp-cli still run if the site root is detected.

Summary report:
* Consolidated report: `/tmp/hz-wp-security-hardening-suite.txt`.
* Each subtask entry includes status (`ran`, `skipped`, or `failed`), return
  code, and the per-task report path.

## Report outputs under /tmp

All Optimize security tasks write reports under `/tmp`:

* `/tmp/hz-wp-security-snapshot.txt`
* `/tmp/hz-wp-hardening-check.txt`
* `/tmp/hz-wp-config-hardening.txt`
* `/tmp/hz-wp-permissions-hardening.txt`
* `/tmp/hz-wp-xmlrpc-block.txt`
* `/tmp/hz-wp-uploads-php-block.txt`
* `/tmp/hz-wp-sensitive-files-block.txt`
* `/tmp/hz-wp-dirlisting-block.txt`
* `/tmp/hz-wp-security-hardening-suite.txt`

## wp-cli requirements

* Requires wp-cli and a WordPress install:
  * Security snapshot
  * Hardening check
  * wp-config hardening (safe)
  * Filesystem permissions hardening (safe)
* No wp-cli required:
  * XML-RPC block (safe)
  * Uploads PHP execution block (safe)
  * Sensitive files web access block (safe)
  * Directory listing block (safe)

## CI smoke timeout knobs

The smoke test entrypoint (`tests/smoke.sh`) reads timeout values from
environment variables and logs the effective values at startup.

* `HZ_SMOKE_STEP_TIMEOUT` (default: `30s`)
  * Applies to each step wrapped by the smoke helper timeout.
* `HZ_SMOKE_QUICK_TRIAGE_TIMEOUT` (default: `60s`)
  * Applies to the quick triage runner inside smoke.
* `HZ_SMOKE_BASELINE_TIMEOUT` (default: `60s`)
  * Applies to baseline regression checks inside smoke.

The `make smoke` target wraps the entire smoke run with `timeout 180s` when the
`timeout` command is available, and passes `HZ_SMOKE_STRICT` as usual.

Example override when running locally:

```bash
HZ_SMOKE_STEP_TIMEOUT=45s \
HZ_SMOKE_QUICK_TRIAGE_TIMEOUT=90s \
HZ_SMOKE_BASELINE_TIMEOUT=120s \
make smoke
```

## Troubleshooting

* **Missing wp-cli**: wp-cli-dependent tasks are skipped. Install wp-cli and
  re-run Optimize to generate reports or apply wp-config/permissions changes.
* **Missing .htaccess on a fresh site**: the XML-RPC block is skipped if the
  root `.htaccess` does not exist. Run permalinks once or create a basic
  `.htaccess`, then re-run the task.
* **Permission denied**: hardening tasks that change files can fail when file
  ownership or permissions are restrictive. Ensure the site root is writable
  by the script runner, then re-run the task.
