# Service restarts and reloads

Use this guide as the canonical reference for service restart/reload steps on
Ubuntu 22.04 / 24.04. All examples use placeholders (for example,
`abc.yourdomain.com` and `/var/www/your-site/html`).

## Reload vs restart

- **Reload** when the service supports reloading configuration without dropping
  connections. Use this after config edits where supported.
- **Restart** when a reload is not supported, after upgrading packages, or when
  a service is wedged. Restarts briefly interrupt traffic.

## Common checks

```bash
systemctl status <service>
```

```bash
journalctl -u <service> -n 100 --no-pager
```

Tail logs while restarting:

```bash
journalctl -u <service> -f
```

## Canonical restart/reload snippets

### OpenLiteSpeed (lsws / openlitespeed)

Detect the service name (varies by install):

```bash
systemctl list-units --type=service | grep -E 'lsws|openlitespeed'
```

Then restart or reload (choose the service name you see above):

```bash
sudo systemctl restart lsws
# or
sudo systemctl restart openlitespeed
```

```bash
sudo systemctl reload lsws
# or
sudo systemctl reload openlitespeed
```

### MariaDB / MySQL

```bash
sudo systemctl restart mariadb
# or
sudo systemctl restart mysql
```

```bash
sudo systemctl reload mariadb
# or
sudo systemctl reload mysql
```

### Redis

```bash
sudo systemctl restart redis-server
```

```bash
sudo systemctl reload redis-server
```

### PHP-FPM (only if present)

Confirm which PHP-FPM units exist before restarting:

```bash
systemctl list-units --type=service | grep -E 'php.*fpm'
```

Then restart or reload the version you have:

```bash
sudo systemctl restart php8.1-fpm
# or
sudo systemctl restart php8.2-fpm
# or
sudo systemctl restart php8.3-fpm
```

```bash
sudo systemctl reload php8.1-fpm
# or
sudo systemctl reload php8.2-fpm
# or
sudo systemctl reload php8.3-fpm
```

## Safe order guidance

- **Only restart what you changed.** If you edited the OpenLiteSpeed vhost
  config, you do not need to restart the database.
- **When multiple services are involved** (for example, after upgrades), restart
  stateful services first:
  1. MariaDB/MySQL
  2. Redis
  3. PHP-FPM (if applicable)
  4. OpenLiteSpeed

## Troubleshooting quick checks

- **Ports:** confirm 80/443 (traffic) and 7080 (OpenLiteSpeed admin) are
  listening when expected.
  ```bash
  sudo ss -ltnp | grep -E ':80|:443|:7080'
  ```
- **Process check:** verify the service is running.
  ```bash
  systemctl status lsws
  ```
- **Recent logs:** review the last 100 lines for errors.
  ```bash
  journalctl -u lsws -n 100 --no-pager
  ```

If the service still fails to start, validate configuration paths (for example,
`/var/www/your-site/html`) and confirm DNS points to
`abc.yourdomain.com` before escalating.
