#!/system/bin/sh
# 92_prune_cache.sh - auto-prune cache HP tiap jam (idempotent)
BB=/data/adb/magisk/busybox
R=/data/local/9root
$BB chroot $R /bin/bash -c 'pgrep -f prune-loop.sh >/dev/null 2>&1 || setsid nohup /bin/bash /root/prune-loop.sh >/dev/null 2>&1 &'
