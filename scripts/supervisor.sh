#!/bin/bash
# supervisor.sh v4 - jaga node & freebuff-proxy tetap hidup + WiFi keepalive + rotasi log
# v4 (2026-09-15): + jaga prune-loop (auto-prune cache tiap jam),
# + cek ELF better_sqlite3.node tiap restart node,
# + rotasi 9router.log dan prune-cache.log
export PATH=/opt/node/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LOG=/opt/data/supervisor.log
FATAL=0

# rotasi log: max 500KB, simpan 200 baris terakhir
rotate_log() {
    local f="$1" max="${2:-500000}" keep="${3:-200}"
    if [ -f "$f" ]; then
        local sz
        sz=$(wc -c < "$f" 2>/dev/null) || return 0
        if [ "$sz" -gt "$max" ]; then
            tail -n "$keep" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
        fi
    fi
}

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

while true; do
    sleep 30

    # rotasi semua log (500KB max, simpan 200 baris terakhir)
    rotate_log "$LOG" 200000 100
    rotate_log /opt/fbp/fbp.log 500000 200
    rotate_log /opt/data/cf-tunnel.log 500000 200
    rotate_log /opt/data/9router.log 500000 200
    rotate_log /root/prune-cache.log 200000 100

    # WiFi keepalive: ping gateway tiap cycle
    ping -c 2 -W 3 192.168.101.1 > /dev/null 2>&1 || \
    ping -c 2 -W 3 8.8.8.8 > /dev/null 2>&1

    # node 9router
    if ! ps aux | grep -E '[c]ustom-server|[n]ext-server' > /dev/null; then
        if od -A n -t x1 /opt/app/node_modules/better-sqlite3/build/Release/better_sqlite3.node 2>/dev/null | head -1 | grep -q '7f 45 4c 46'; then
            log "driver DB OK (ELF ARM)"
        else
            log "FATAL: better_sqlite3.node bukan ELF ARM - driver DB akan gagal, jangan timpa node_modules dari Windows"
        fi
        log "node MATI -> restart"
        cd /opt/app
        HOME=/root HOSTNAME=0.0.0.0 PORT=20128 NODE_ENV=production INITIAL_PASSWORD=9routerhp \
        NODE_OPTIONS="--max-old-space-size=384 --max-semi-space-size=16" \
        setsid node custom-server.js >> /opt/data/9router.log 2>&1 &
        renice -n -5 -p $! >/dev/null 2>&1
        FATAL=$((FATAL+1))
    fi

    # freebuff-proxy
    if ! ps aux | grep '[f]reebuff-proxy' | grep -v grep > /dev/null; then
        log "freebuff MATI -> restart"
        cd /opt/fbp
        HOME=/root nohup ./freebuff-proxy >> /opt/fbp/fbp.log 2>&1 &
        renice -n -5 -p $! >/dev/null 2>&1
        FATAL=$((FATAL+1))
    fi

    # prune-loop (auto-prune cache tiap jam, backup bila 92 service.d gagal jalan)
    if ! pgrep -f '[p]rune-loop.sh' > /dev/null 2>&1; then
        setsid nohup /bin/bash /root/prune-loop.sh > /dev/null 2>&1 &
        log "prune-loop mati -> dinyalakan"
    fi

    # batasi restart rate: max 5 per jam, reset tiap 60 cycle (~30 menit)
    if [ "$FATAL" -ge 5 ]; then
        log "restart rate limit reached, sleeping 10 min"
        sleep 600
        FATAL=0
    fi

    cd /
done
