#!/bin/bash
# fix-watchdog2.sh - fix false-negative sup-watch + mutual watchdog + restart bersih
set +e
BB=/data/adb/magisk/busybox
SW=/proc/1/root/data/adb/service.d/90_sup_watch.sh
PL=/root/prune-loop.sh

echo "=== 0. status awal ==="
ps aux | grep -E "[s]upervisor.sh|[p]rune-loop"

echo "=== 1. prune-loop v2 (mutual watchdog: jaga supervisor tiap 60 dtk) ==="
cp -p $PL $PL.bak.$(date +%Y%m%d)
cat > $PL <<'PEOF'
#!/bin/sh
# prune-loop.sh v2 - prune cache tiap 1 jam + jaga supervisor (mutual watchdog)
# v2 (2026-09-26): + cek supervisor tiap 60 dtk (sup-watch host bisa false-negative)
i=0
while true; do
  sleep 60
  i=$((i+1))
  pgrep -f '[s]upervisor.sh' >/dev/null 2>&1 || setsid nohup /bin/bash /root/supervisor.sh >/dev/null 2>&1 &
  if [ $i -ge 60 ]; then
    i=0
    /root/prune-cache.sh 2>/dev/null
  fi
done
PEOF
chmod 755 $PL
sh -n $PL && echo "prune-loop syntax OK"

echo "=== 2. sup-watch v2 (deteksi pakai ps global, bukan pgrep chroot) ==="
cp -p $SW $SW.bak.$(date +%Y%m%d)
cat > $SW <<'SEOF'
#!/system/bin/sh
# 90_sup_watch v2 - jaga supervisor + cloudflared (host context)
# v2 (2026-09-26): deteksi supervisor pakai busybox ps (global PID),
# karena pgrep via chroot dari konteks magisk selalu false-negative.
if [ "$1" != "bg" ]; then
    BB=/data/adb/magisk/busybox
    $BB setsid sh "$0" bg </dev/null >/dev/null 2>&1 &
    exit 0
fi
BB=/data/adb/magisk/busybox
R=/data/local/9root
LOG=/data/local/tmp/sup-watch.log
CF=/data/local/9root/opt/bin/cloudflared
TT=/data/local/9root/opt/data/tunnel-token.txt
CFLOG=/data/local/9root/opt/data/cf-tunnel.log
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> $LOG; }
while true; do
    sleep 60
    if [ -f $LOG ] && [ $($BB wc -c < $LOG) -gt 200000 ]; then
        $BB tail -100 $LOG > $LOG.tmp && mv $LOG.tmp $LOG
    fi
    if ! $BB ps | grep -q "[s]upervisor.sh"; then
        $BB chroot $R /bin/bash -c 'setsid nohup /root/supervisor.sh >/dev/null 2>&1 &'
        log "supervisor mati -> dinyalakan (ps-check)"
    fi
    if [ -z "$($BB pidof cloudflared)" ]; then
        "$CF" tunnel run --token-file "$TT" >> $CFLOG 2>&1 &
        log "cloudflared mati -> dinyalakan"
    fi
done
SEOF
chmod 755 $SW
sh -n $SW && echo "sup-watch syntax OK"

echo "=== 3. restart sup-watch (kill lama, start versi baru dari host context) ==="
SWPID=$($BB ps | awk '/[s]up_watch/ {print $1; exit}')
if [ -n "$SWPID" ]; then kill $SWPID 2>/dev/null; echo "killed sup-watch PID $SWPID"; fi
sleep 2
$BB chroot /proc/1/root /data/adb/magisk/busybox sh /data/adb/service.d/90_sup_watch.sh
sleep 3
$BB ps | grep "[s]up_watch" | head -3

echo "=== 4. restart prune-loop (versi v2) ==="
OLDPID=$(pgrep -f "[p]rune-loop" 2>/dev/null)
[ -n "$OLDPID" ] && kill $OLDPID 2>/dev/null
sleep 1
setsid nohup /bin/bash /root/prune-loop.sh >/dev/null 2>&1 &
sleep 2
ps aux | grep "[p]rune-loop"

echo "=== 5. verifikasi akhir ==="
ps aux | grep -E "[s]upervisor.sh|[p]rune-loop"
echo "=== DONE ==="
