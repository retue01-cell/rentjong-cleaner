#!/bin/bash
# test-chain.sh - diagnosa kenapa sup-watch gagal start supervisor
echo "=== T0: siapa yang start supervisor di boot ==="
grep -n "supervisor" /proc/1/root/data/adb/service.d/*.sh 2>/dev/null | head -12
echo "=== T1: busybox ps lihat supervisor? ==="
/proc/1/root/data/adb/magisk/busybox ps 2>/dev/null | grep -i "supervis" | head -5
echo "T1-exit=$?"
echo "=== T2: chroot bash dasar ==="
BB=/proc/1/root/data/adb/magisk/busybox
R=/proc/1/root/data/local/9root
$BB chroot $R /bin/bash -c 'echo hello-chroot'
echo "T2-exit=$?"
echo "=== T3: chroot pgrep pola persis sup-watch ==="
$BB chroot $R /bin/bash -c "pgrep -f '[s]upervisor.sh' >/dev/null 2>&1"
echo "T3-exit=$?"
echo "=== T4: chroot pgrep longgar (tampil hasil) ==="
$BB chroot $R /bin/bash -c "pgrep -f supervisor"
echo "T4-exit=$?"
echo "=== T5: spawn sleep via chroot (pola restart) ==="
$BB chroot $R /bin/bash -c 'setsid nohup /bin/sleep 40 >/dev/null 2>&1 &'
echo "T5-spawn-exit=$?"
sleep 3
ps aux | grep "[s]leep 40"
echo "T5-verify-exit=$?"
echo "=== T6: trik chroot ke root Android ==="
$BB chroot /proc/1/root /system/bin/sh -c 'echo host-sh-ok; id'
echo "T6-exit=$?"
echo "=== T7: status SELinux ==="
cat /proc/1/root/sys/fs/selinux/enforce 2>/dev/null; getenforce 2>/dev/null
echo "=== done ==="
