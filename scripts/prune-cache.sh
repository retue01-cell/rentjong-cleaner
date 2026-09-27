#!/bin/sh
# prune-cache.sh v3 (2026-09-27) - prune cache + storage HP Rentjong (dari dalam chroot)
# Dipanggil tiap jam oleh prune-loop.sh, atau manual: /root/prune-cache.sh
# Log: /root/prune-cache.log
# Semua ambang bisa di-override via env untuk testing, contoh:
#   GEN_CACHE_LIMIT=1 /root/prune-cache.sh
LOG=/root/prune-cache.log
say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG" 2>/dev/null; }
size_kb() { du -sk "$1" 2>/dev/null | cut -f1; }
free_kb() { df -k /data 2>/dev/null | awk 'NR==2 {print $4}'; }

# Ambang (KB)
NEXT_CACHE_LIMIT=${NEXT_CACHE_LIMIT:-102400}
NPM_CACHE_LIMIT=${NPM_CACHE_LIMIT:-204800}
GEN_CACHE_LIMIT=${GEN_CACHE_LIMIT:-102400}
APT_LISTS_LIMIT=${APT_LISTS_LIMIT:-153600}
GOPATH_LIMIT=${GOPATH_LIMIT:-204800}
GOCACHE_LIMIT=${GOCACHE_LIMIT:-102400}
APPBAK_LIMIT=${APPBAK_LIMIT:-153600}
LOG_LIMIT=${LOG_LIMIT:-2048}
FREE_WARN=${FREE_WARN:-409600}
FREE_CRIT=${FREE_CRIT:-204800}

prune_dir_gt() {
  path=$1 limit=$2
  s=$(size_kb "$path")
  if [ -n "$s" ] && [ "$s" -gt "$limit" ]; then
    rm -rf "${path:?}"/* 2>/dev/null
    say "pruned $path (${s}KB > ${limit}KB)"
  fi
}

# 1) Next.js build cache 9router
prune_dir_gt /opt/app/.next/cache "$NEXT_CACHE_LIMIT"

# 2) npm cache
prune_dir_gt /root/.npm/_cacache "$NPM_CACHE_LIMIT"

# 3) cache user (go-build, pip, node-gyp)
prune_dir_gt /root/.cache "$GEN_CACHE_LIMIT"

# 4) apt lists
prune_dir_gt /var/lib/apt/lists "$APT_LISTS_LIMIT"

# 5) cache module Go - v3: ini penyebab utama /data penuh, v2 sengaja tidak prune
prune_dir_gt /root/tmp/gopath/pkg "$GOPATH_LIMIT"

# 6) cache build Go - v3 fix: path aslinya /opt/data/gocache, bukan /root/tmp/gocache
prune_dir_gt /opt/data/gocache "$GOCACHE_LIMIT"
prune_dir_gt /opt/data/gomodcache "$GOCACHE_LIMIT"

# 7) backup app lama: sisakan 1 yang terbaru, hapus sisanya kalau total lewat ambang
bak_kb=$(du -sk /opt/app.bak-* 2>/dev/null | awk '{s+=$1} END {print s+0}')
bak_n=$(ls -d /opt/app.bak-* 2>/dev/null | wc -l)
if [ "$bak_n" -gt 1 ] && [ "$bak_kb" -gt "$APPBAK_LIMIT" ]; then
  for d in $(ls -dt /opt/app.bak-* 2>/dev/null | tail -n +2); do
    rm -rf "$d" 2>/dev/null && say "hapus backup lama $d"
  done
  say "backup app: sisakan $(ls -dt /opt/app.bak-* 2>/dev/null | head -1)"
fi

# 8) trim log service (>2MB, sisakan 200 baris)
for f in /opt/fbp/fbp.log /opt/data/cf-tunnel.log /opt/data/9router.log \
         /opt/o2a/o2a.log /opt/data/supervisor.log /root/cf-tunnel.log; do
  [ -f "$f" ] || continue
  s=$(size_kb "$f")
  if [ -n "$s" ] && [ "$s" -gt "$LOG_LIMIT" ]; then
    tail -200 "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
    say "trimmed $f (${s}KB)"
  fi
done

# 9) guard free space. Part yang hanya terlihat dari host (dalvik-cache, /data/local/tmp)
#    ditangani 91_host_maintain.sh di /data/adb/service.d.
f=$(free_kb)
if [ -n "$f" ] && [ "$f" -lt "$FREE_WARN" ]; then
  say "PERINGATAN: /data free ${f}KB (< ${FREE_WARN}KB)"
fi
if [ -n "$f" ] && [ "$f" -lt "$FREE_CRIT" ]; then
  prune_dir_gt /root/tmp "$GOPATH_LIMIT"
  prune_dir_gt /root/.npm "$NPM_CACHE_LIMIT"
  say "mode agresif: /data free ${f}KB"
fi

exit 0
