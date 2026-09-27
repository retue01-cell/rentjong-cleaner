#!/bin/bash
# prune-loop.sh v3 (2026-09-27) - prune cache tiap 1 jam + jaga supervisor (mutual watchdog)
# v2 (2026-09-26): + cek supervisor tiap 60 dtk
# v3: fix operator background v2 ( Whole `pgrep || setsid ...` becoming background, checking is not blocking)
#     + heartbeat ke prune-cache.log sebagai bukti hidup
i=0
while true; do
  sleep 60
  i=$((i+1))

  if ! pgrep -f '[s]upervisor.sh' >/dev/null 2>&1; then
    setsid nohup /bin/bash /root/supervisor.sh >/dev/null 2>&1 &
  fi

  if [ $((i % 60)) -eq 0 ]; then
    /root/prune-cache.sh 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') heartbeat: prune cache dijalankan, free=$(df -k /data | awk 'NR==2 {print $4}')KB" >> /root/prune-cache.log 2>/dev/null
    i=0
  fi
done
