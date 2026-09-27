#!/system/bin/sh
# 91_host_maintain.sh (2026-09-27) - rotasi log host + bersihkan cache ART saat disk kritis
# Dipakai karena /data (luar chroot) tidak terlihat dari prune-cache.sh.
# Dijalankan Magisk saat boot: /data/adb/service.d/
BB=/data/adb/magisk/busybox
LOG=/data/local/tmp/host-maintain.log
say() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG" 2>/dev/null; }
free_kb() { df -k /data 2>/dev/null | awk 'NR==2 {print $4}'; }

# 1) rotasi log di /data/local/tmp (>512KB, sisakan 200 baris)
for f in /data/local/tmp/*.log; do
  [ -f "$f" ] || continue
  s=$($BB du -k "$f" 2>/dev/null | cut -f1)
  if [ -n "$s" ] && [ "$s" -gt 512 ]; then
    $BB tail -n 200 "$f" > "$f.tmp" 2>/dev/null && $BB mv "$f.tmp" "$f" && say "rotated $f (${s}KB)"
  fi
done

# 2) disk kritis (<300MB free): bersihkan dalvik-cache. Rebuild ART bikin boot
#    lambat, jadi hanya di detik terakhir, bukan jadwal rutin.
f=$(free_kb)
if [ -n "$f" ] && [ "$f" -lt 307200 ]; then
  s=$($BB du -sk /data/dalvik-cache 2>/dev/null | cut -f1)
  $BB rm -rf /data/dalvik-cache/* 2>/dev/null
  say "KRITIS: /data free ${f}KB -> dalvik-cache dibersihkan (${s}KB). Boot berikutnya lambat."
fi

# 3) anr/tombstones biar tidak menumpuk (>3 hari)
$BB find /data/anr /data/tombstones -type f -mtime +3 2>/dev/null | while read x; do
  $BB rm -f "$x" 2>/dev/null && say "removed old $x"
done

exit 0
