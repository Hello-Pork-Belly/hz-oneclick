# Install modes (Full stack vs Frontend-only)

The installer supports two deployment patterns. Choose **LOMP Full Stack (Local
DB/Redis)** when you want the simplest single-host setup: WordPress, database,
and Redis all run on the same machine. This is the easiest path for small to
medium sites and for single-server stacks.

Choose **LNMP-Lite (Frontend-only; Remote DB/Redis)** when you want the
WordPress frontend on a lighter node and host database/Redis on a separate
machine or managed service. This is ideal for low-memory VPS hosts, or when you
prefer to place DB/Redis on a stronger server or private network.

## Required inputs for frontend-only mode

When using **LNMP-Lite (Frontend-only; Remote DB/Redis)**, you must supply:

- **DB host** (IP or hostname)
- **DB port** (default `3306`)
- **DB name**
- **DB user**
- **DB password** (entered securely in the script prompt)
- **Redis host** and **Redis port** when Redis is enabled

If Redis is disabled in the current flow, the Redis host/port prompts can be
skipped.

## Connectivity checklist

Before installing in frontend-only mode, verify that the frontend node can
reach the remote services:

- Ensure network reachability (private VLAN, WireGuard, Tailscale, or VPC
  routing is OK).
- Open ports: `3306` for MySQL/MariaDB, `6379` for Redis.
- Confirm DNS resolution if you use hostnames.

Basic checks (run from the frontend node):

```bash
# MySQL/MariaDB TCP reachability
nc -vz <db-host> 3306

# Redis TCP reachability
nc -vz <redis-host> 6379
```

Database authentication (avoid putting passwords directly in argv):

```bash
# Create a temporary defaults file with 0600 permissions.
cat > /tmp/mysql-secure.cnf <<'CNF'
[client]
user=<db-user>
password=<db-password>
host=<db-host>
port=3306
CNF
chmod 600 /tmp/mysql-secure.cnf

mysql --defaults-extra-file=/tmp/mysql-secure.cnf -e "SELECT 1;"
rm -f /tmp/mysql-secure.cnf
```

Redis authentication:

```bash
# Use REDISCLI_AUTH so the password is not exposed in argv.
REDISCLI_AUTH='<redis-password>' redis-cli -h <redis-host> -p 6379 PING
```

## Security notes

- Do **not** pass database passwords in command-line arguments. Use the
  installer’s secure prompt or temporary config files like `--defaults-extra-file`.
- Keep firewall rules tight: only allow the frontend node to access DB/Redis.
- Rotate credentials if they were exposed in shell history or logs.

## Common failure modes and quick fixes

- **DNS resolution fails**: verify `/etc/resolv.conf` and the hostname, or use
  a direct IP address.
- **TCP connection fails**: check security groups/firewalls and whether the
  DB/Redis service is listening on the expected interface.
- **Access denied (MySQL)**: confirm the DB user is granted for the frontend
  node’s source host (e.g., `user@'%'` or `user@'<frontend-host>'`).
- **Redis NOAUTH**: confirm the password and `requirepass` configuration.

If issues persist, re-run the installer and re-enter the remote connection
inputs.
