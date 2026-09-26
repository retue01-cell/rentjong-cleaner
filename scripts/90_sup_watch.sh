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
