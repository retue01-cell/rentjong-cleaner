#!/bin/bash
# fix-watchdog3.sh - restart sup-watch v2 pakai path busybox yang benar (dari chroot)
set +e
BB=/proc/1/root/data/adb/magisk/busybox

echo "=== 1. kill sup-watch lama ==="
$BB ps | grep "[s]up_watch" | head -5
SWPID=$($BB ps | awk '/[s]up_watch/ {print $1; exit}')
if [ -n "$SWPID" ]; then kill $SWPID 2>/dev/null; echo "killed PID $SWPID"; fi
sleep 2

echo "=== 2. start sup-watch v2 (host context via chroot /proc/1/root) ==="
$BB chroot /proc/1/root /system/bin/sh /data/adb/service.d/90_sup_watch.sh
sleep 4

echo "=== 3. verifikasi sup-watch baru jalan ==="
$BB ps | grep "[s]up_watch" | head -5

echo "=== 4. tes deteksi supervisor (ps global dari host context) ==="
$BB ps | grep "[s]upervisor.sh" | head -3
echo "=== DONE ==="
