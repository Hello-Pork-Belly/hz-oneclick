# File permissions and ownership

This guide provides a single, canonical set of permissions and ownership
recommendations. Keeping permissions tight protects configuration secrets,
prevents unauthorized changes, and still lets the web server update only what it
must (for example, uploads).

## Recommended ownership & perms

| Path | Purpose | Ownership | Permissions |
| --- | --- | --- | --- |
| `/var/www/your-site/html` | WordPress site root | `root:root` | Dirs `755`, files `644` |
| `/var/www/your-site/html/wp-content` | Plugins/themes (writable if you use in-dashboard updates) | `www-data:www-data` | Dirs `755`, files `644` |
| `/var/www/your-site/html/wp-content/uploads` | Media uploads | `www-data:www-data` | Dirs `755`, files `644` |
| `/var/www/your-site/html/wp-config.php` | WordPress config | `root:root` | `600` |
| `/usr/local/lsws/conf` | OLS/LSWS config (placeholder) | `root:root` | Dirs `755`, files `644` |
| `/usr/local/lsws/admin/conf` | OLS/LSWS admin config (placeholder) | `root:root` | Dirs `755`, files `644` |
| `/var/log/your-site` | Site logs (placeholder) | `root:root` | Dirs `755`, files `644` |
| `/usr/local/lsws/logs` | OLS/LSWS logs (placeholder) | `root:root` | Dirs `755`, files `644` |

## Apply ownership

Use a single ownership model for consistency:

- `root:root` for configuration and WordPress core files.
- `www-data:www-data` only where the web server must write (uploads and optional
  plugin/theme updates).

```bash
sudo chown -R root:root /var/www/your-site/html
sudo chown -R www-data:www-data /var/www/your-site/html/wp-content
sudo chown -R www-data:www-data /var/www/your-site/html/wp-content/uploads
```

## Apply permissions

```bash
sudo find /var/www/your-site/html -type d -exec chmod 755 {} +
sudo find /var/www/your-site/html -type f -exec chmod 644 {} +
sudo chmod 600 /var/www/your-site/html/wp-config.php
```

If your logs are written by a service user, keep the owner as `root:root` but
ensure that service can write via group permissions or logrotate (do not make
log directories world-writable).

## Check your work

```bash
ls -la /var/www/your-site/html
ls -la /var/www/your-site/html/wp-content
ls -la /var/www/your-site/html/wp-content/uploads
```

Find any world-writable paths and fix them:

```bash
sudo find /var/www/your-site/html -perm -0002 -print
```

## What NOT to do

- Avoid `chmod 777` on any file or directory.
- Do not make `wp-config.php` writable by the web server.
- Do not `chown -R www-data:www-data` the entire site unless you accept the
  security trade-offs and understand the risk of accidental writes.
