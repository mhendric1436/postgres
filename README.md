# postgres

Makefile-driven PostgreSQL 18 lifecycle manager for local development.

## Requirements

```
brew install postgresql@18
```

## Quick start

```sh
make init    # initialize a new cluster in ./data/
make start   # start the server
make psql    # open a shell
make stop    # stop the server
```

## Configuration

All variables have sensible defaults and can be overridden via a `.env` file or on the command line.

| Variable | Default | Description |
|---|---|---|
| `PG_VERSION` | `18` | PostgreSQL major version |
| `PG_PORT` | `5432` | Listener port |
| `PG_USER` | current user | Superuser name |
| `PG_DB` | current user | Default database |
| `PG_DATA` | `./data` | Cluster data directory |
| `PG_LOG` | `./logs/postgres.log` | Server log file |
| `PG_BACKUP` | `./backups` | Backup output directory |

**Example `.env`:**
```
PG_PORT=5433
PG_DB=myapp
```

**Example one-off override:**
```sh
make psql PG_DB=myapp
```

## Targets

### Lifecycle

| Target | Description |
|---|---|
| `make init` | Initialize a new cluster in `PG_DATA` |
| `make start` | Start the cluster |
| `make stop` | Stop the cluster (fast mode) |
| `make restart` | Stop then start |
| `make reload` | Reload config without restart |
| `make status` | Cluster status + active connections |
| `make destroy` | Stop and delete the cluster (irreversible) |

### Databases & users

| Target | Description |
|---|---|
| `make createdb PG_DB=mydb` | Create a database |
| `make dropdb PG_DB=mydb` | Drop a database |
| `make createuser ROLE=app ROLEPASS=secret` | Create a login role |
| `make psql PG_DB=mydb` | Open a psql shell |

### Schema

| Target | Description |
|---|---|
| `make migrate PG_DB=mydb` | Run `migrations/*.sql` in sorted order |
| `make schema PG_DB=mydb` | Dump DDL to stdout |

### Backup & restore

| Target | Description |
|---|---|
| `make backup PG_DB=mydb` | `pg_dump -Fc` to `./backups/<db>_<timestamp>.dump` |
| `make backup-globals` | Dump roles and tablespaces |
| `make restore FILE=backups/foo.dump PG_DB=mydb` | Restore a dump |
| `make backups-list` | List available backups |

### Diagnostics

| Target | Description |
|---|---|
| `make slow-queries` | Queries running longer than 5 seconds |
| `make locks` | Blocking lock chains |
| `make index-usage PG_DB=mydb` | Index vs sequential scan rates per table |
| `make table-sizes PG_DB=mydb` | Top 20 tables by total size |
| `make cache-hit PG_DB=mydb` | Buffer cache hit rates |

### Maintenance

| Target | Description |
|---|---|
| `make vacuum PG_DB=mydb` | `VACUUM ANALYZE` (add `TABLE=foo` for one table) |
| `make vacuum-full PG_DB=mydb` | `VACUUM FULL` — locks table, use with care |
| `make reindex PG_DB=mydb` | `REINDEX DATABASE` |
| `make kill-idle` | Terminate connections idle for > 10 minutes |

### Config

| Target | Description |
|---|---|
| `make edit-conf` | Open `postgresql.conf` in `$EDITOR` |
| `make edit-hba` | Open `pg_hba.conf` in `$EDITOR` |
| `make show-conf` | Show all non-default runtime settings |

### Extensions

| Target | Description |
|---|---|
| `make extensions PG_DB=mydb` | List installed extensions |
| `make install-ext EXT=pg_stat_statements PG_DB=mydb` | Install an extension |

## Directory layout

```
.
├── Makefile
├── .env              # optional local overrides (not committed)
├── data/             # cluster data directory (gitignored)
├── logs/             # server logs (gitignored)
├── backups/          # pg_dump output (gitignored)
└── migrations/       # *.sql files applied by `make migrate`
```
