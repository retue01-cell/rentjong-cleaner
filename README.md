# rentjong-cleaner — Pembersih Otomatis HP Rentjong

> Auto-prune cache + rantai watchdog untuk HP Android 5.1 (Rentjong OS, ARMv7, Magisk, chroot Debian di `/data/local/9root`). Menjaga disk tetap lega dan semua service tetap hidup 24/7.

Berjalan produksi di HP Rentjong sejak 14 Sep 2026. Diperbaiki besar-besaran 26 Sep 2026 (lihat [docs/SESSION-20260926.md](docs/SESSION-20260926.md)).

## Arsitektur (3 lapis)

```
Magisk service.d (boot)
├── 92_prune_cache.sh   → jalankan prune-loop di chroot (sekali saat boot)
└── 90_sup_watch.sh     → watchdog HOST: jaga supervisor + cloudflared tiap 60 dtk
        │
        ▼ chroot /data/local/9root
    supervisor.sh       → loop 30 dtk: jaga 9router + freebuff-proxy + WiFi + rotasi log
    prune-loop.sh v2    → loop 60 dtk: jaga supervisor (mutual) + prune cache tiap 1 jam
        │
        ▼
    prune-cache.sh      → eksekutor pembersihan dengan ambang batas (lihat tabel)
```

## Ambang batas pembersihan (`prune-cache.sh`)

| # | Target | Ambang | Aksi |
|---|---|---|---|
| 1 | `/opt/app/.next/cache` (9Router) | >100MB | hapus isi cache |
| 2 | `/root/.npm` | >200MB | hapus `_cacache` + `_logs` |
| 3 | `/root/.cache` | >100MB | hapus isi |
| 4 | `/var/lib/apt/lists` | >150MB | hapus + `apt-get clean` |
| 5 | `/opt/freebuff-proxy-src` | >200MB | hapus `vendor` + `.git` |
| 6 | log service (fbp/9router/batproxy/o2a/cf-tunnel) | >2MB | sisakan 200 baris |
| 7 | `/root/tmp/gocache` (Go build cache) | >100MB | hapus isi (**`gopath` TIDAK disentuh** — cache toolchain) |

Semua aksi dicatat ke `/root/prune-cache.log`.

## Rotasi log (lapis supervisor)

- `supervisor.log` 200KB, `fbp.log`/`cf-tunnel.log`/`9router.log` 500KB, `prune-cache.log` 200KB
- `sup-watch.log` 200KB (oleh sup-watch)
- Semua "sisakan 100–200 baris terakhir".

## Jebakan yang terbukti (jangan diulang)

| Jebakan | Detail |
|---|---|
| `pgrep` via chroot dari konteks Magisk = false-negative | Selalu exit 2 walau proses hidup → sup-watch lama spam "supervisor mati" tiap menit dan rantai watchdog putus senyap. **Fix: deteksi pakai `busybox ps \| grep "[s]upervisor.sh"` (global PID).** |
| Prune-loop mati tidak ada yang menghidupkan | Dulu hanya `92_prune_cache.sh` (boot). **Fix: sup-watch host + supervisor v4 + mutual watchdog di prune-loop v2.** |
| gocache membengkak saat build | 221MB terukur 26 Sep 2026, tidak tercakup prune lama. **Fix: item #7, tapi `gopath` wajib disimpan** (cache toolchain Go, hemat ±35 menit build). |
| `busybox` path beda di dalam vs luar chroot | Di chroot: `/data/adb/magisk/busybox` tidak ada → pakai `/proc/1/root/data/adb/magisk/busybox` saat akses dari dalam chroot. |
| SSH dropbear LAN "banner exchange" | Normal di HP ini; retry setelah 10–60 dtk. Jalur alternatif: `adb forward tcp:18022 tcp:8022`. |

## Cara pasang (ringkas)

Semua dari PC via SSH (key `rentjong_key`), kirim file dengan base64:

```powershell
$key = "D:\Aplikasi\opencode-config\ext\rentjong-9router\rentjong_key"
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("scripts\prune-cache.sh"))
ssh -i $key -p 8022 root@192.168.101.18 "echo $b64 | base64 -d > /root/prune-cache.sh; chmod 755 /root/prune-cache.sh"
```

Penempatan:
| File | Lokasi di HP |
|---|---|
| `prune-cache.sh`, `prune-loop.sh`, `supervisor.sh` | `/root/` (dalam chroot) |
| `92_prune_cache.sh`, `90_sup_watch.sh` | `/data/adb/service.d/` (host, autostart Magisk) |

## Verifikasi cepat

```bash
# di chroot (via SSH)
ps aux | grep -E "[s]upervisor.sh|[p]rune-loop"     # keduanya harus ada
tail -5 /root/prune-cache.log                        # riwayat prune
tail -3 /data/local/tmp/sup-watch.log                # tidak boleh spam tiap menit
df / | tail -1                                       # sisa disk
curl -s http://127.0.0.1:13457/healthz | head -c 80  # freebuff-proxy
```

## File

```
scripts/
├── prune-cache.sh        ← eksekutor pembersihan (7 item, ambang batas)
├── prune-loop.sh         ← loop v2: mutual watchdog + prune tiap jam
├── supervisor.sh         ← penjaga service + WiFi + rotasi log
├── 92_prune_cache.sh     ← autostart Magisk (boot)
├── 90_sup_watch.sh       ← watchdog host v2 (ps-based)
├── fix-watchdog.sh       ← skrip patch 26 Sep (gocache + restart rantai)
├── fix-watchdog2.sh      ← patch sup-watch v2 + prune-loop v2
├── fix-watchdog3.sh      ← restart sup-watch pakai path busybox benar
└── test-chain.sh         ← diagnosa rantai watchdog (T1–T7)
docs/
└── SESSION-20260926.md   ← catatan lengkap sesi perbaikan
```

## Lisensi

MIT
