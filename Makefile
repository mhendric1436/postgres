# PostgreSQL lifecycle management
# Requires: postgresql (brew install postgresql@16 or adjust PG_VERSION below)

PG_VERSION   ?= 18
PG_PORT      ?= 5432
PG_USER      ?= $(shell whoami)
PG_DB        ?= $(PG_USER)
PG_DATA      ?= $(CURDIR)/data
PG_LOG       ?= $(CURDIR)/logs/postgres.log
PG_BACKUP    ?= $(CURDIR)/backups
PG_BIN       ?= $(shell brew --prefix postgresql@$(PG_VERSION) 2>/dev/null)/bin

# Allow override via .env if present
-include .env

PSQL  := $(PG_BIN)/psql   -p $(PG_PORT) -U $(PG_USER)
PG_CTL := $(PG_BIN)/pg_ctl -D $(PG_DATA) -l $(PG_LOG)
STAMP := $(shell date +%Y%m%d_%H%M%S)

.DEFAULT_GOAL := help

# ─── Help ────────────────────────────────────────────────────────────────────

.PHONY: help
help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nPostgreSQL Lifecycle Manager\n\n"} \
	  /^[a-zA-Z_-]+:.*##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "  Config (override via .env or make VAR=value):"
	@echo "    PG_VERSION=$(PG_VERSION)  PG_PORT=$(PG_PORT)  PG_USER=$(PG_USER)"
	@echo "    PG_DB=$(PG_DB)  PG_DATA=$(PG_DATA)"
	@echo ""

# ─── Init & Teardown ─────────────────────────────────────────────────────────

.PHONY: init
init: ## Initialize a new cluster in PG_DATA
	@[ -d "$(PG_DATA)" ] && { echo "Cluster already exists at $(PG_DATA). Run 'make destroy' first."; exit 1; } || true
	@mkdir -p "$(dir $(PG_LOG))" "$(PG_BACKUP)"
	$(PG_BIN)/initdb -D "$(PG_DATA)" -U "$(PG_USER)" --auth=trust --encoding=UTF8 --locale=C
	@echo "port = $(PG_PORT)" >> "$(PG_DATA)/postgresql.conf"
	@echo "log_statement = 'all'" >> "$(PG_DATA)/postgresql.conf"
	@echo "Cluster initialized. Run 'make start' to begin."

.PHONY: destroy
destroy: stop ## Stop and delete the cluster (irreversible)
	@echo "Deleting cluster at $(PG_DATA) …"
	@rm -rf "$(PG_DATA)"
	@echo "Done."

# ─── Lifecycle ───────────────────────────────────────────────────────────────

.PHONY: start
start: ## Start the cluster
	@[ -d "$(PG_DATA)" ] || { echo "No cluster at $(PG_DATA). Run 'make init' first."; exit 1; }
	@mkdir -p "$(dir $(PG_LOG))"
	$(PG_CTL) start
	@echo "PostgreSQL $(PG_VERSION) listening on port $(PG_PORT)"

.PHONY: stop
stop: ## Stop the cluster (fast mode)
	@$(PG_CTL) status > /dev/null 2>&1 || { echo "Already stopped."; exit 0; }
	$(PG_CTL) stop -m fast

.PHONY: restart
restart: stop start ## Restart the cluster

.PHONY: reload
reload: ## Reload config without restart (pg_ctl reload)
	$(PG_CTL) reload

.PHONY: status
status: ## Show cluster status and active connections
	@$(PG_CTL) status
	@echo ""
	@$(PSQL) -d postgres -c "SELECT pid, usename, application_name, client_addr, state, query_start, left(query,80) AS query FROM pg_stat_activity WHERE pid <> pg_backend_pid() ORDER BY query_start;" 2>/dev/null || true

# ─── Database & Users ────────────────────────────────────────────────────────

.PHONY: createdb
createdb: ## Create PG_DB (make createdb PG_DB=mydb)
	$(PG_BIN)/createdb -p $(PG_PORT) -U $(PG_USER) "$(PG_DB)"

.PHONY: dropdb
dropdb: ## Drop PG_DB (make dropdb PG_DB=mydb)
	$(PG_BIN)/dropdb -p $(PG_PORT) -U $(PG_USER) --if-exists "$(PG_DB)"

.PHONY: createuser
createuser: ## Create a role (make createuser ROLE=app ROLEPASS=secret)
	@[ -n "$(ROLE)" ] || { echo "Usage: make createuser ROLE=<name> [ROLEPASS=<pw>]"; exit 1; }
	$(PSQL) -d postgres -c "CREATE ROLE $(ROLE) LOGIN$(if $(ROLEPASS), PASSWORD '$(ROLEPASS)',);"

.PHONY: psql
psql: ## Open psql shell (make psql PG_DB=mydb)
	$(PSQL) -d "$(PG_DB)"

# ─── Schema ──────────────────────────────────────────────────────────────────

.PHONY: migrate
migrate: ## Run SQL files in migrations/ in order (make migrate PG_DB=mydb)
	@[ -d migrations ] || { echo "No migrations/ directory found."; exit 1; }
	@for f in $$(ls migrations/*.sql 2>/dev/null | sort); do \
	  echo "  applying $$f …"; \
	  $(PSQL) -d "$(PG_DB)" -f "$$f"; \
	done

.PHONY: schema
schema: ## Dump the schema of PG_DB (stdout)
	$(PG_BIN)/pg_dump -p $(PG_PORT) -U $(PG_USER) --schema-only "$(PG_DB)"

# ─── Backup & Restore ────────────────────────────────────────────────────────

.PHONY: backup
backup: ## pg_dump PG_DB to PG_BACKUP/<db>_<timestamp>.dump
	@mkdir -p "$(PG_BACKUP)"
	$(PG_BIN)/pg_dump -p $(PG_PORT) -U $(PG_USER) -Fc -f "$(PG_BACKUP)/$(PG_DB)_$(STAMP).dump" "$(PG_DB)"
	@echo "Backup saved: $(PG_BACKUP)/$(PG_DB)_$(STAMP).dump"

.PHONY: backup-globals
backup-globals: ## Dump roles and tablespaces to PG_BACKUP/globals_<timestamp>.sql
	@mkdir -p "$(PG_BACKUP)"
	$(PG_BIN)/pg_dumpall -p $(PG_PORT) -U $(PG_USER) --globals-only \
	  -f "$(PG_BACKUP)/globals_$(STAMP).sql"
	@echo "Globals saved: $(PG_BACKUP)/globals_$(STAMP).sql"

.PHONY: restore
restore: ## Restore a dump (make restore FILE=backups/mydb_20240101.dump PG_DB=mydb)
	@[ -n "$(FILE)" ] || { echo "Usage: make restore FILE=<path.dump> [PG_DB=<target>]"; exit 1; }
	$(PG_BIN)/pg_restore -p $(PG_PORT) -U $(PG_USER) -d "$(PG_DB)" \
	  --no-owner --role="$(PG_USER)" -v "$(FILE)"

.PHONY: backups-list
backups-list: ## List available backups
	@ls -lht "$(PG_BACKUP)" 2>/dev/null || echo "No backups found in $(PG_BACKUP)"

# ─── Logs & Diagnostics ──────────────────────────────────────────────────────

.PHONY: logs
logs: ## Tail the server log
	tail -f "$(PG_LOG)"

.PHONY: slow-queries
slow-queries: ## Show queries running longer than 5 seconds
	$(PSQL) -d postgres -c \
	  "SELECT pid, now() - query_start AS duration, usename, state, left(query,120) AS query \
	   FROM pg_stat_activity \
	   WHERE state <> 'idle' AND query_start < now() - interval '5 seconds' \
	   ORDER BY duration DESC;"

.PHONY: locks
locks: ## Show blocking lock chains
	$(PSQL) -d postgres -c \
	  "SELECT bl.pid AS blocked_pid, a.usename AS blocked_user, \
	          kl.pid AS blocking_pid, ka.usename AS blocking_user, \
	          a.query AS blocked_query \
	   FROM pg_catalog.pg_locks bl \
	   JOIN pg_catalog.pg_stat_activity a  ON a.pid = bl.pid \
	   JOIN pg_catalog.pg_locks kl ON kl.transactionid = bl.transactionid AND kl.pid <> bl.pid \
	   JOIN pg_catalog.pg_stat_activity ka ON ka.pid = kl.pid \
	   WHERE NOT bl.granted;"

.PHONY: index-usage
index-usage: ## Show index hit rates per table in PG_DB
	$(PSQL) -d "$(PG_DB)" -c \
	  "SELECT relname, \
	          100 * idx_scan / nullif(idx_scan + seq_scan, 0) AS index_hit_pct, \
	          n_live_tup AS rows \
	   FROM pg_stat_user_tables \
	   ORDER BY index_hit_pct NULLS LAST, rows DESC \
	   LIMIT 20;"

.PHONY: table-sizes
table-sizes: ## Show top 20 tables by size in PG_DB
	$(PSQL) -d "$(PG_DB)" -c \
	  "SELECT relname AS table, \
	          pg_size_pretty(pg_total_relation_size(relid)) AS total, \
	          pg_size_pretty(pg_relation_size(relid)) AS heap, \
	          pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS indexes \
	   FROM pg_catalog.pg_statio_user_tables \
	   ORDER BY pg_total_relation_size(relid) DESC \
	   LIMIT 20;"

.PHONY: cache-hit
cache-hit: ## Show buffer cache hit rates
	$(PSQL) -d "$(PG_DB)" -c \
	  "SELECT 'index hit rate' AS metric, \
	          round(sum(idx_blks_hit) * 100.0 / nullif(sum(idx_blks_hit + idx_blks_read), 0), 2) AS pct \
	   FROM pg_statio_user_indexes \
	   UNION ALL \
	   SELECT 'table hit rate', \
	          round(sum(heap_blks_hit) * 100.0 / nullif(sum(heap_blks_hit + heap_blks_read), 0), 2) \
	   FROM pg_statio_user_tables;"

# ─── Maintenance ─────────────────────────────────────────────────────────────

.PHONY: vacuum
vacuum: ## VACUUM ANALYZE PG_DB (or TABLE= for one table)
	$(PSQL) -d "$(PG_DB)" -c "VACUUM ANALYZE$(if $(TABLE), $(TABLE),);"

.PHONY: vacuum-full
vacuum-full: ## VACUUM FULL PG_DB (locks table — use with care)
	$(PSQL) -d "$(PG_DB)" -c "VACUUM FULL$(if $(TABLE), $(TABLE),);"

.PHONY: reindex
reindex: ## REINDEX DATABASE PG_DB
	$(PSQL) -d "$(PG_DB)" -c "REINDEX DATABASE $(PG_DB);"

.PHONY: kill-idle
kill-idle: ## Terminate idle connections older than 10 minutes
	$(PSQL) -d postgres -c \
	  "SELECT pg_terminate_backend(pid) \
	   FROM pg_stat_activity \
	   WHERE state = 'idle' \
	     AND query_start < now() - interval '10 minutes' \
	     AND pid <> pg_backend_pid();"

# ─── Config ──────────────────────────────────────────────────────────────────

.PHONY: edit-conf
edit-conf: ## Open postgresql.conf in \$$EDITOR
	$${EDITOR:-vi} "$(PG_DATA)/postgresql.conf"

.PHONY: edit-hba
edit-hba: ## Open pg_hba.conf in \$$EDITOR
	$${EDITOR:-vi} "$(PG_DATA)/pg_hba.conf"

.PHONY: show-conf
show-conf: ## Show non-default runtime settings
	$(PSQL) -d postgres -c \
	  "SELECT name, setting, unit, source FROM pg_settings WHERE source <> 'default' ORDER BY name;"

# ─── Extensions ──────────────────────────────────────────────────────────────

.PHONY: extensions
extensions: ## List installed extensions in PG_DB
	$(PSQL) -d "$(PG_DB)" -c "\dx"

.PHONY: install-ext
install-ext: ## Install an extension (make install-ext EXT=pg_stat_statements)
	@[ -n "$(EXT)" ] || { echo "Usage: make install-ext EXT=<extension_name>"; exit 1; }
	$(PSQL) -d "$(PG_DB)" -c "CREATE EXTENSION IF NOT EXISTS $(EXT);"
