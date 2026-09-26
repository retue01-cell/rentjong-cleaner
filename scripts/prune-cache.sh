#!/bin/sh
# Prune cache HP Rentjong (9router, freebuff-proxy, batproxy, opencode2api).
# Jalankan dari supervisor.sh loop atau manual. Log: /root/prune-cache.log
LOG=/root/prune-cache.log
say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG" 2>/dev/null; }
size_kb() { du -sk "$1" 2>/dev/null | cut -f1; }

# Ambang (KB)
NEXT_CACHE_LIMIT=102400
NPM_CACHE_LIMIT=204800
GEN_CACHE_LIMIT=102400
APT_LISTS_LIMIT=153600
FBP_SRC_LIMIT=204800
LOG_LIMIT=2048

prune_dir_gt() {
  path=$1 limit=$2
  s=$(size_kb "$path")
  [ -n "$s" ] && [ "$s" -gt "$limit" ] && { rm -rf "$path"/* 2>/dev/null; say "pruned $path (${s}KB)"; }
}

# 1) Next.js build cache (9router) - isi cache saja, jangan sentuh build
s=$(size_kb /opt/app/.next/cache)
if [ -n "$s" ] && [ "$s" -gt "$NEXT_CACHE_LIMIT" ]; then
  rm -rf /opt/app/.next/cache/* 2>/dev/null
  say "pruned .next/cache (${s}KB)"
fi

# 2) npm cache
s=$(size_kb /root/.npm)
if [ -n "$s" ] && [ "$s" -gt "$NPM_CACHE_LIMIT" ]; then
  rm -rf /root/.npm/_cacache /root/.npm/_logs 2>/dev/null
  say "pruned .npm (${s}KB)"
fi

# 3) cache user (go-build, pip)
prune_dir_gt /root/.cache "$GEN_CACHE_LIMIT"

# 4) apt lists
s=$(size_kb /var/lib/apt/lists)
if [ -n "$s" ] && [ "$s" -gt "$APT_LISTS_LIMIT" ]; then
  rm -rf /var/lib/apt/lists/* 2>/dev/null
  apt-get clean 2>/dev/null
  say "pruned apt lists (${s}KB)"
fi

# 5) freebuff-proxy source build (modul Go hasil build; build ulang re-download)
s=$(size_kb /opt/freebuff-proxy-src)
if [ -n "$s" ] && [ "$s" -gt "$FBP_SRC_LIMIT" ]; then
  rm -rf /opt/freebuff-proxy-src/vendor /opt/freebuff-proxy-src/.git 2>/dev/null
  say "pruned fbp-src heavy dirs (${s}KB)"
fi

# 6) log semua service >2MB: sisakan 200 baris terakhir
for f in /opt/fbp/fbp.log /root/cf-tunnel.log /opt/data/9router.log /opt/batproxy/batproxy.log /opt/o2a/o2a.log; do
  if [ -f "$f" ]; then
    s=$(size_kb "$f")
    if [ "$s" -gt "$LOG_LIMIT" ]; then
      tail -200 "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
      say "trimmed $f (${s}KB)"
    fi
  fi
done

# 7) gocache Go build cache (boleh dihapus; gopath disimpan utuh)
s=$(size_kb /root/tmp/gocache)
if [ -n "$s" ] && [ "$s" -gt 102400 ]; then
  rm -rf /root/tmp/gocache/* 2>/dev/null
  say "pruned gocache (${s}KB)"
fi

exit 0
