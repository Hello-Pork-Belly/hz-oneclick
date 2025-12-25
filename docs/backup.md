# Backups

This guide outlines prerequisites and safety checks for backup workflows. All
examples use placeholders (e.g., `abc.yourdomain.com`, `/var/www/your-site/html`).

## Prerequisites

### Required tools

Install or verify these commands are available:

- `tar` and `gzip` for packaging file backups.
- `rsync` or `rclone` to copy backups to another location.
- `mysqldump` (or the MariaDB/MySQL client tools) to export the database.
- Optional: `openssl` or `gpg` if you encrypt backups at rest.
- Optional: `sha256sum` to verify backup integrity.

### Access and permissions

Ensure you can read everything you need to back up:

- `root` or `sudo` access to read WordPress files in `/var/www/your-site/html`.
- Database credentials from your configuration or environment (do not hard-code
  secrets into scripts).
- Credentials for your destination storage (local path, SSH target, or object
  storage), scoped to the backup location only.

### Storage requirements

Plan for enough space and retention:

- Keep at least 2x the size of your site files plus database dumps.
- Define a retention window (for example, daily backups for 14 days).
- Prefer encrypted backups and an offsite destination (separate host or bucket).

### Safety notes

- Regularly test restores in a non-production environment.
- Verify integrity with checksums before deleting older backups.
- Avoid embedding secrets in scripts; use config files or environment variables.

## Quick checklist

- [ ] Verify required tools (`tar`, `gzip`, `rsync`/`rclone`, `mysqldump`) exist.
- [ ] Confirm access to `/var/www/your-site/html` and the database.
- [ ] Validate destination storage credentials and available space.
- [ ] Enable encryption if backups leave the server.
- [ ] Schedule and document retention expectations.

## Restore drill (recommended)

After a test restore, confirm:

- The site loads at a placeholder domain like `abc.yourdomain.com`.
- The database connects and core tables are present.
- File permissions and ownership match your expected values.
- Any secrets or config values are updated for the target environment.
