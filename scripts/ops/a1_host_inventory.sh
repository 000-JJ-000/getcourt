#!/usr/bin/env bash
# Read-only Oracle Ampere A1 host inventory for GetCourt tennis deployment planning.
# Ubuntu/ARM64 compatible. No package installs, no sudo required for basic checks.
#
# Usage:
#   bash scripts/ops/a1_host_inventory.sh
#   bash scripts/ops/a1_host_inventory.sh | tee ~/a1-inventory.txt
#
# Does NOT: read .env files, dump container env, docker inspect, print secrets/logs,
#            modify the filesystem (except stdout/stderr redirected by the operator).

set -u

section() {
  printf '\n======== %s ========\n' "$1"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

safe_run() {
  # Run a command; on failure print a one-line note (no stack traces of secrets).
  local label="$1"
  shift
  if "$@" 2>/dev/null; then
    return 0
  fi
  printf '(unavailable: %s)\n' "$label"
  return 0
}

echo "GetCourt A1 host inventory (read-only)"
echo "generated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
echo "note=Sanitize public IPs, domains, usernames before sharing"

# --- 1. OS / kernel / arch / uptime ---
section "1 OS kernel architecture uptime"
safe_run uname uname -a
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "PRETTY_NAME=${PRETTY_NAME:-}"
  echo "ID=${ID:-}"
  echo "VERSION_ID=${VERSION_ID:-}"
else
  echo "(unavailable: /etc/os-release)"
fi
echo -n "uname_m="
safe_run uname_m uname -m
if have uptime; then
  uptime
else
  echo "(unavailable: uptime)"
fi

# --- 2. CPU count and load ---
section "2 CPU count and load"
if have nproc; then
  echo -n "nproc="
  nproc
else
  echo "(unavailable: nproc)"
fi
if have lscpu; then
  lscpu 2>/dev/null | egrep 'Architecture|CPU\(s\)|Thread|Core|Model name|Socket|CPU max MHz|CPU min MHz' || true
else
  echo "(unavailable: lscpu)"
fi
if [[ -r /proc/loadavg ]]; then
  echo -n "loadavg="
  cat /proc/loadavg
fi
if [[ -r /proc/pressure/cpu ]]; then
  echo -n "psi_cpu="
  head -n 1 /proc/pressure/cpu
fi

# --- 3. RAM / available / swap ---
section "3 Memory and swap"
if have free; then
  free -h
else
  echo "(unavailable: free)"
fi
if [[ -r /proc/meminfo ]]; then
  egrep '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree):' /proc/meminfo || true
fi
if [[ -r /proc/pressure/memory ]]; then
  echo -n "psi_memory="
  head -n 1 /proc/pressure/memory
fi

# --- 4. Disk capacity and inodes ---
section "4 Disk capacity and inodes"
if have df; then
  df -hT
  echo "--- inodes ---"
  df -i
else
  echo "(unavailable: df)"
fi
if have lsblk; then
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null || true
fi

# --- 5. Docker / Compose availability ---
section "5 Docker and Compose"
if have docker; then
  docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}} Arch={{.Server.Arch}}' 2>/dev/null \
    || docker version 2>&1 | head -n 20 \
    || echo "(docker present but not usable — check group membership; no sudo attempted)"
else
  echo "(docker not found on PATH)"
fi
if have docker; then
  docker compose version 2>/dev/null || echo "(docker compose plugin unavailable)"
fi
if have docker-compose; then
  docker-compose version 2>/dev/null || true
fi

# --- 6. Running containers and resource usage ---
section "6 Running containers and resource usage"
if have docker; then
  if docker ps >/dev/null 2>&1; then
    docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
    echo "--- docker stats (one shot; no inspect) ---"
    docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}' 2>/dev/null || true
    echo "--- docker system df ---"
    docker system df 2>/dev/null || true
  else
    echo "(docker daemon not reachable without elevated permissions — skipped container listing)"
  fi
else
  echo "(skipped: no docker)"
fi

# --- 7. Existing Compose project names ---
section "7 Compose projects"
if have docker && docker compose version >/dev/null 2>&1; then
  docker compose ls 2>/dev/null || echo "(compose ls unavailable)"
else
  echo "(skipped)"
fi

# --- 8. Published ports and host listeners ---
section "8 Published ports and host listeners"
echo "--- docker published ports (from ps) ---"
if have docker && docker ps >/dev/null 2>&1; then
  docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null || true
fi
echo "--- host listeners (addresses may need redaction) ---"
if have ss; then
  ss -tuln 2>/dev/null || true
elif have netstat; then
  netstat -tuln 2>/dev/null || true
else
  echo "(ss/netstat unavailable)"
fi
echo "--- port 3010 probe (TCP listen check) ---"
if have ss; then
  if ss -tuln 2>/dev/null | grep -E '[:.]3010\b' >/dev/null; then
    echo "port_3010=IN_USE (see listeners above; redact IPs if sharing)"
  else
    echo "port_3010=NOT_SEEN_IN_LISTENERS"
  fi
else
  echo "port_3010=UNKNOWN (no ss)"
fi

# --- 9. Reverse proxy detection ---
section "9 Reverse proxy detection"
for bin in caddy nginx traefik httpd apache2; do
  if have "$bin"; then
    echo "binary_present=${bin} path=$(command -v "$bin")"
  fi
done
for unit in caddy nginx traefik apache2 httpd; do
  if have systemctl; then
    state=$(systemctl is-active "$unit" 2>/dev/null || true)
    if [[ -n "${state}" && "${state}" != "unknown" ]]; then
      echo "systemd_unit=${unit} state=${state}"
    fi
  fi
done
echo "--- config path presence (names only; contents not read) ---"
for path in /etc/caddy /etc/nginx /etc/nginx/sites-enabled /etc/traefik /etc/apache2; do
  if [[ -e "$path" ]]; then
    echo "path_exists=${path}"
    if [[ -d "$path" ]]; then
      # Filenames only — do not cat configs (may contain emails, domains, secrets).
      ls -1 "$path" 2>/dev/null | sed 's/^/  entry=/' || true
    fi
  fi
done
# Dockerized proxies (name/image only)
if have docker && docker ps >/dev/null 2>&1; then
  docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | egrep -i 'caddy|nginx|traefik|proxy|httpd' || echo "(no obvious proxy containers by name/image)"
fi

# --- 10. Firewall status (read-only, best-effort, no sudo) ---
section "10 Firewall status (no sudo)"
if have ufw; then
  ufw status 2>/dev/null || echo "(ufw present but status requires privileges)"
else
  echo "(ufw not found)"
fi
if have firewall-cmd; then
  firewall-cmd --state 2>/dev/null || echo "(firewalld present but state requires privileges)"
else
  echo "(firewall-cmd not found)"
fi
if have iptables; then
  iptables -L -n 2>/dev/null | head -n 40 || echo "(iptables list requires privileges — skipped)"
else
  echo "(iptables not found)"
fi
if have nft; then
  nft list ruleset 2>/dev/null | head -n 40 || echo "(nft list requires privileges — skipped)"
else
  echo "(nft not found)"
fi
echo "note=Also review OCI VCN security lists / NSGs in the console (not collected here)"

# --- 11. Backup directory presence (names only) ---
section "11 Backup directory presence (names only)"
for path in /var/backups /var/backups/tennis "$HOME/backups" "$HOME/getcourt-backups" /opt/backups; do
  if [[ -d "$path" ]]; then
    echo "dir_exists=${path}"
    # Top-level names only; do not recurse into dump contents.
    ls -1 "$path" 2>/dev/null | head -n 50 | sed 's/^/  entry=/' || true
  else
    echo "dir_missing=${path}"
  fi
done

section "DONE"
echo "Sanitize before sharing: public IPs, reverse-DNS names, usernames, unique hostnames,"
echo "OCI identifiers, and any unexpected tokens in path names."
echo "Safe to keep: arch, OCPU/RAM totals, free disk%, container names/images/status, port numbers."
