# Logging locations

This page centralizes common log locations for services used in this stack. All
examples use placeholders; replace domain and site slug values with your own
(e.g. `abc.yourdomain.com`, `/var/www/your-site`).

## Common log paths (placeholders)

| Component | Typical log location(s) | Notes |
| --- | --- | --- |
| OpenLiteSpeed / LSWS (access) | `/usr/local/lsws/logs/access.log` | Access log for web traffic. |
| OpenLiteSpeed / LSWS (error) | `/usr/local/lsws/logs/error.log` | Server-side errors and startup issues. |
| PHP (php-fpm or service logs) | `/var/log/php-fpm.log` | Log name can include version (e.g. `php8.x-fpm.log`). |
| MariaDB/MySQL | `/var/log/mysql/error.log` or `/var/log/mariadb/mariadb.log` | Path varies by package. |
| Redis | `/var/log/redis/redis-server.log` | Redis server log (if file logging enabled). |
| UFW | `/var/log/ufw.log` | Firewall log (if enabled). |
| Fail2ban | `/var/log/fail2ban.log` | Ban and jail activity. |
| acme.sh / certificate issuance | `/root/.acme.sh/acme.sh.log` | acme.sh client log (if used). |
| systemd/journald | `journalctl -u <service>` | Use journalctl for service logs. |

## Discovery commands

Use these commands to confirm actual log locations on Ubuntu:

```bash
systemctl status <service>
journalctl -u <service> --no-pager -n 200
ls /usr/local/lsws/logs/
sudo find /var/log -maxdepth 2 -type f | grep -E 'nginx|lsws|mysql|mariadb|redis|php|fail2ban|ufw'
```
