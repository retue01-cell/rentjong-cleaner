# rentjong-cleaner — Pembersih Otomatis HP Rentjong

> Auto-prune cache + rantai watchdog untuk HP Android 5.1 (Rentjong OS, ARMv7, Magisk, chroot Debian di `/data/local/9root`). Menjaga disk tetap lega dan semua service tetap hidup 24/7.

Berjalan produksi di HP Rentjong sejak 14 Sep 2026. Diperbaiki besar-besaran 26 Sep 2026 (lihat [docs/SESSION-20260926.md](docs/SESSION-20260926.md)), lalu `prune-cache.sh` + `prune-loop.sh` naik ke **v3** pada 27 Sep 2026 (lihat [docs/SESSION-20260927.md](docs/SESSION-20260927.md)).

## Arsitektur (3 lapis)

```
Magisk service.d (boot)
├── 92_prune_cache.sh   → jalankan prune-loop di chroot (sekali saat boot)
└── 90_sup_watch.sh     → watchdog HOST: jaga supervisor + cloudflared tiap 60 dtk
        │
        ▼ chroot /data/local/9root
    supervisor.sh       → loop 30 dtk: jaga 9router + freebuff-proxy + WiFi + rotasi log
    prune-loop.sh v3    → loop 60 dtk: jaga supervisor (mutual) + prune cache tiap 1 jam + heartbeat
        │
        ▼
    prune-cache.sh v3   → eksekutor pembersihan dengan ambang batas (lihat tabel)
```

## Ambang batas pembersihan (`prune-cache.sh` v3)

| # | Target | Ambang | Aksi | Status |
|---|---|---|---|---|
| 1 | `/opt/app/.next/cache` (9Router) | >100MB | hapus isi cache | lama |
| 2 | `/root/.npm/_cacache` | >200MB | hapus cache | lama (path dipersempit) |
| 3 | `/root/.cache` (go-build, pip, node-gyp) | >100MB | hapus isi | lama |
| 4 | `/var/lib/apt/lists` | >150MB | hapus isi | lama |
| 5 | `/root/tmp/gopath/pkg` | >200MB | hapus isi | **baru** — v2 sengaja tidak prune, hasil 783MB |
| 6 | `/opt/data/gocache` + `/opt/data/gomodcache` | >100MB | hapus isi | **path diperbaiki** — v2 prune `/root/tmp/gocache` yang tidak pernah ada |
| 7 | `/opt/app.bak-*` | >150MB total | sisakan 1 backup terbaru | **baru** |
| 8 | 6 file log service (fbp/9router/o2a/cf-tunnel/supervisor) | >2MB | sisakan 200 baris | tambah 2 file |
| 9 | guard free-space `/data` | <400MB / <200MB | warning di log, lalu mode agresif (`/root/tmp` + `/root/.npm`) | **baru** |

Item 5 (v2) insightful: `gopath` **tidak** boleh dipragma karena rebuild freebuff-proxy butuh unduh ulang modul ±35 menit, tapi `gopath/pkg` 783MB adalah penyebab `/data` penuh 89%. v3 memangkas hanya kalau lewat 200MB.

Semua ambang bisa di-override via env untuk testing:

```bash
GEN_CACHE_LIMIT=1 /root/prune-cache.sh   # paksa aturan /root/.cache jalan
tail -5 /root/prune-cache.log
```

Semua aksi dicatat ke `/root/prune-cache.log`. Kalau tidak ada apa pun yang dipangkas, log tetap kosong — itu normal, bukan error. `prune-loop.sh` v3 menulis heartbeat tiap jam sebagai bukti hidup.

## Rotasi log (lapis supervisor)

- `supervisor.log` 200KB, `fbp.log`/`cf-tunnel.log`/`9router.log` 500KB, `prune-cache.log` 200KB
- `sup-watch.log` 200KB (oleh sup-watch)
- Semua "sisakan 100–200 baris terakhir".

## Perawatan sisi host: `91_host_maintain.sh`

Bagian `/data` di luar chroot (`/data/dalvik-cache`, `/data/local/tmp/*.log`) **tidak terlihat** dari `prune-cache.sh`, jadi butuh skrip host terpisah. Isi `91_host_maintain.sh`:

1. Rotasi `/data/local/tmp/*.log` (>512KB → 200 baris)
2. Kalau `/data` free <300MB: bersihkan `/data/dalvik-cache` (rebuild ART bikin boot lambat, jadi hanya di detik terakhir)
3. Hapus `anr`/`tombstones` yang umurnya >3 hari

**Belum terpasang** (lihat jebakan SELinux di bawah). Log: `/data/local/tmp/host-maintain.log`.

## Jebakan yang terbukti (jangan diulang)

| Jebakan | Detail |
|---|---|
| `pgrep` via chroot dari konteks Magisk = false-negative | Selalu exit 2 walau proses hidup → sup-watch lama spam "supervisor mati" tiap menit dan rantai watchdog putus senyap. **Fix: deteksi pakai `busybox ps \| grep "[s]upervisor.sh"` (global PID).** |
| Prune-loop mati tidak ada yang menghidupkan | Dulu hanya `92_prune_cache.sh` (boot). **Fix: sup-watch host + supervisor v4 + mutual watchdog di prune-loop v2.** |
| gocache membengkak saat build | 221MB terukur 26 Sep 2026, tidak tercakup prune lama. **Fix: item #6, path `/opt/data/gocache`.** |
| `gopath` = 783MB tidak pernah disentuh | Penyebab `/data` penuh 89% selama berminggu-minggu tanpa memicu satu pun aturan v2. **Fix 27 Sep: item #5 dengan ambang 200MB.** |
| Path `gocache` di v2 salah total | v2 prune `/root/tmp/gocache`, cache aslinya di `/opt/data/gocache` — jadi aturan itu **tidak pernah jalan sekali pun**. Fix: baca lokasi cache dari `go env GOCACHE`, jangan menebak. |
| Operator `&` di prune-loop v2 | `pgrep ... \|\| setsid ... &` membuat seluruh list di-background, jadi pengecekan tidak blocking. v3 pakai `if ! pgrep ...; then ... & fi`. |
| `/data/adb/service.d/*` read-only untuk context Magisk | `chmod` berhasil, tulis konten ditolak (`can't create ...: Permission denied`). Tidak bisa menambah atau menambal skrip boot dari adb/su. **Fix: reinstall Magisk/ROM, atau pasang dari custom recovery yang tidak dibatasi SELinux.** Konsekuensi: `91_host_maintain.sh` tidak bisa dipasang permanen (dampak kecil: log host ~189KB, dalvik-cache hanya perlu saat free <300MB). |
| `busybox` path beda di dalam vs luar chroot | Di chroot: `/data/adb/magisk/busybox` tidak ada → pakai `/proc/1/root/data/adb/magisk/busybox` saat akses dari dalam chroot. |
| SSH dropbear LAN "banner exchange" | Normal di HP ini; retry setelah 10–60 dtk. Jalur alternatif: `adb forward tcp:18022 tcp:8022`. |
| Burst `adb.exe` bisa bikin PC bluescreen | Puluhan panggilan `adb.exe` beruntun dalam satu sesi = pemicu bluescreen yang sudah terjadi 2 kali di PC ini. Untuk pekerjaan pemeliharaan, pakai SSH (dropbear `:8022`) — nol `adb.exe`. |

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
| `91_host_maintain.sh` | `/data/adb/service.d/` — **belum bisa dipasang**, lihat jebakan SELinux |

Validasi sintaks sebelum dipasang (hentikan kalau ada error):

```bash
ssh -i $key -p 8022 root@192.168.101.18 \
  'sh -n /root/prune-cache.sh.new && bash -n /root/prune-loop.sh.new && \
   cp -p /root/prune-cache.sh /root/prune-cache.sh.bak.$(date +%Y%m%d) && \
   cp -p /root/prune-loop.sh /root/prune-loop.sh.bak.$(date +%Y%m%d) && \
   mv /root/prune-cache.sh.new /root/prune-cache.sh && \
   mv /root/prune-loop.sh.new /root/prune-loop.sh && \
   chmod 755 /root/prune-cache.sh /root/prune-loop.sh'
# restart prune-loop; supervisor menghidupkan ulang otomatis <= 30 detik
ssh -i $key -p 8022 root@192.168.101.18 'kill $(pgrep -f "[p]rune-loop.sh")'
```

## Verifikasi cepat

```bash
# di chroot (via SSH)
ps aux | grep -E "[s]upervisor.sh|[p]rune-loop"     # keduanya harus ada
tail -5 /root/prune-cache.log                        # riwayat prune + heartbeat per jam
tail -3 /data/local/tmp/sup-watch.log                # tidak boleh spam tiap menit
df / | tail -1                                       # sisa disk
curl -s http://127.0.0.1:13457/healthz | head -c 80  # freebuff-proxy
```

Tes fungsi prune tanpa menunggu 1 jam:

```bash
GEN_CACHE_LIMIT=1 /root/prune-cache.sh               # harus muncul "pruned /root/.cache"
tail -2 /root/prune-cache.log
```

## File

```
scripts/
├── prune-cache.sh        ← eksekutor pembersihan (9 item, ambang batas, env-overridable)
├── prune-loop.sh         ← loop v3: mutual watchdog + prune tiap jam + heartbeat
├── supervisor.sh         ← penjaga service + WiFi + rotasi log
├── 92_prune_cache.sh     ← autostart Magisk (boot)
├── 90_sup_watch.sh       ← watchdog host v2 (ps-based)
├── 91_host_maintain.sh   ← rotasi log host + prune darurat dalvik-cache (belum terpasang)
├── fix-watchdog.sh       ← skrip patch 26 Sep (gocache + restart rantai)
├── fix-watchdog2.sh      ← patch sup-watch v2 + prune-loop v2
├── fix-watchdog3.sh      ← restart sup-watch pakai path busybox benar
└── test-chain.sh         ← diagnosa rantai watchdog (T1–T7)
docs/
├── SESSION-20260926.md   ← catatan lengkap sesi perbaikan
└── SESSION-20260927.md   ← audit v2 vs v3 + hasil cleanup 1.9GB
```

## Lisensi

MIT
