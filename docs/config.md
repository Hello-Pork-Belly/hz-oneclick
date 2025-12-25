# Configuration file locations

Configuration file paths vary by OS version, package source, and service
variants. Use the discovery commands below to confirm the active configuration
on your host before editing anything.

## How to locate active configuration

Run the commands that match your stack to see where each service reads its
configuration:

```bash
# OpenLiteSpeed: show unit file and any overrides
systemctl cat lsws

# OpenLiteSpeed config tree
ls -la /usr/local/lsws/conf

# Find vhost configs by domain placeholder
find /usr/local/lsws/conf/vhosts -name "vhconf.conf" -maxdepth 3

# PHP: list loaded ini files
php --ini

# MariaDB/MySQL: show default options file search order
mariadb --help | rg -i "Default options"

# Redis: confirm version and inspect unit for config path
redis-server --version
systemctl cat redis-server

# UFW rules and defaults
ls -la /etc/ufw

# Fail2ban config tree
ls -la /etc/fail2ban

# Systemd overrides for any service
systemctl cat <unit>
```

## Common configuration and log locations (placeholders)

Use these as starting points and replace placeholders like `your-site` and
`abc.yourdomain.com` with your real values.

| Component | Common config location (placeholder) | Common log location (placeholder) | Notes / how to verify |
| --- | --- | --- | --- |
| OpenLiteSpeed core | `/usr/local/lsws/conf/httpd_config.conf` | `/usr/local/lsws/logs/error.log` | `systemctl cat lsws` shows the unit and any overrides. |
| OpenLiteSpeed vhost/site | `/usr/local/lsws/conf/vhosts/abc.yourdomain.com/vhconf.conf` | `/usr/local/lsws/logs/abc.yourdomain.com.error.log` | Vhost docroot is typically `/var/www/your-site/html`. |
| Site content | `/var/www/your-site/html` | `/var/www/your-site/html/wp-content/debug.log` | Only present if app logging is enabled. |
| PHP (CLI/FPM/LSAPI) | `/etc/php/8.x/cli/php.ini`, `/etc/php/8.x/fpm/php.ini`, or `/usr/local/lsws/lsphp*/etc/php.ini` | `/var/log/php8.x-fpm.log` or `/usr/local/lsws/logs/stderr.log` | Run `php --ini` to see the loaded ini files. |
| MariaDB/MySQL | `/etc/mysql/my.cnf`, `/etc/mysql/mariadb.conf.d/50-server.cnf`, `/etc/mysql/conf.d/*.cnf` | `/var/log/mysql/error.log` or `/var/log/mariadb/mariadb.log` | `mariadb --help | rg -i "Default options"` prints the config search order. |
| Redis | `/etc/redis/redis.conf` or `/etc/redis/redis-server.conf` | `/var/log/redis/redis-server.log` | `systemctl cat redis-server` shows the config file path. |
| UFW firewall | `/etc/ufw/ufw.conf`, `/etc/ufw/before.rules`, `/etc/ufw/after.rules`, `/etc/default/ufw` | `/var/log/ufw.log` | `ls -la /etc/ufw` to review rule files. |
| Fail2ban | `/etc/fail2ban/jail.conf`, `/etc/fail2ban/jail.d/*.conf`, `/etc/fail2ban/fail2ban.conf` | `/var/log/fail2ban.log` | `ls -la /etc/fail2ban` to see overrides. |
| Systemd unit overrides | `/etc/systemd/system/<unit>.service.d/*.conf` | N/A | `systemctl cat <unit>` shows drop-ins and vendor unit files. |
