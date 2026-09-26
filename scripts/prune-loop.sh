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
