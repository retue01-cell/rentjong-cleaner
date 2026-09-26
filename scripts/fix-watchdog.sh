#!/bin/bash
# fix-watchdog.sh - pulihkan rantai watchdog + tambah prune gocache
# Konteks: dijalankan dari dalam chroot (SSH). Host diakses via /proc/1/root.
set +e
BB=/data/adb/magisk/busybox
R=/data/local/9root

procs() {
  for p in /proc/[0-9]*; do
    c=$(tr '\0' ' ' < $p/cmdline 2>/dev/null)
    case "$c" in
      *supervisor.sh*|*prune-loop*|*sup_watch*|*cloudflared*|*custom-server*|*freebuff-proxy*)
        [ -n "$c" ] && echo "PID ${p#/proc/}: $(echo $c | cut -c1-90)";;
    esac
  done
}

echo "=== PROSES SEKARANG ==="
procs

echo "=== SUP-WATCH LOG ==="
tail -6 /proc/1/root/data/local/tmp/sup-watch.log 2>&1

echo "=== PATCH prune-cache.sh: tambah gocache ==="
if grep -q gocache /root/prune-cache.sh; then
  echo "gocache: sudah ada di prune-cache.sh"
else
  cp -p /root/prune-cache.sh /root/prune-cache.sh.bak.$(date +%Y%m%d)
  awk 'BEGIN{done=0}
  /^exit 0/ && !done {
    print "# 7) gocache Go build cache (boleh dihapus; gopath disimpan utuh)"
    print "s=$(size_kb /root/tmp/gocache)"
    print "if [ -n \"$s\" ] && [ \"$s\" -gt 102400 ]; then"
    print "  rm -rf /root/tmp/gocache/* 2>/dev/null"
    print "  say \"pruned gocache (${s}KB)\""
    print "fi"
    print ""
    done=1
  }
  {print}' /root/prune-cache.sh > /root/prune-cache.sh.new && mv /root/prune-cache.sh.new /root/prune-cache.sh
  chmod 755 /root/prune-cache.sh
  echo "gocache: ADDED"
  bash -n /root/prune-cache.sh && echo "syntax: OK"
fi

echo "=== NYALAKAN YANG MATI ==="
if ps aux 2>/dev/null | grep -q "[s]upervisor.sh"; then
  echo "supervisor: sudah jalan"
else
  setsid nohup /bin/bash /root/supervisor.sh >/dev/null 2>&1 &
  echo "supervisor: STARTED"
fi

if ps aux 2>/dev/null | grep -q "[p]rune-loop.sh"; then
  echo "prune-loop: sudah jalan"
else
  setsid nohup /bin/bash /root/prune-loop.sh >/dev/null 2>&1 &
  echo "prune-loop: STARTED"
fi

if ps aux 2>/dev/null | grep -q "sup_watch"; then
  echo "sup-watch: sudah jalan"
else
  chroot /proc/1/root /data/adb/magisk/busybox setsid sh /data/adb/service.d/90_sup_watch.sh bg 2>&1
  echo "sup-watch: STARTED (via /proc/1/root)"
fi

sleep 8
echo "=== VERIFIKASI (8 dtk kemudian) ==="
procs

echo "=== TES PRUNE-CACHE (versi baru) ==="
/bin/sh /root/prune-cache.sh
echo "exit=$?"
tail -5 /root/prune-cache.log 2>&1
echo "=== SELESAI ==="
