# Dashboard Kas & Kegiatan — ATLAS

PWA monitoring kegiatan + kas harian untuk trip/operasional. Offline-first
(localStorage), sinkron opsional ke server sendiri.

## Akses

| | |
|---|---|
| **App (live)** | https://alpha3402.github.io/dashboard-kas/ |
| **API** | https://kas.atlastechcompany.web.id (`/data`, `/reports`) |
| **Repo** | https://github.com/alpha3402/dashboard-kas |
| **Backup** | Google Drive → `My Drive/VPS ATLAS/DASHBOARD-KAS` |

## Struktur

```
index.html      seluruh app (single-file: UI + logika + sinkron)
v2.html         halaman penyelamat/perbaikan endpoint (bersihkan cache + heal sesi)
fix.html        pembersih service-worker & cache
sw.js           service worker (mode offline)
manifest.json   metadata PWA
icon-*.png      ikon app (Android/iOS/maskable)
backup-gdrive.sh  backup otomatis ke Google Drive
```

Backend terpisah: `D:\ATLAS-DATA\dashboard-kas-backend` (server.py + db.sqlite3 +
watchdog + konfigurasi Cloudflare Tunnel).

## Arsitektur sinkron

- Data ditulis ke `localStorage` lebih dulu → app tetap jalan tanpa jaringan.
- Jika `dk_api_v1` terisi, app mengirim ke API (header `x-auth`) dan menandai
  status di header: **Server online / Mode lokal**.
- Saat gagal jaringan: toast "Gagal sinkron ke server — data tetap tersimpan lokal"
  dan transaksi masuk antrean `pending` (tidak ada kegagalan senyap).
- Hapus transaksi/kegiatan ikut terkirim ke server saat role **Ajudan**.
- Tambah & edit data terkirim ke server untuk **semua role** (endpoint `/tx`,
  `/keg` melakukan upsert).

## Role & akun

| Role | Akses |
|---|---|
| **Ajudan** | Tambah **dan edit** data, hapus data, upload/hapus foto, backup/reset |
| **Driver** | Tambah **dan edit** data, upload foto. **Tidak bisa hapus** (tombol hapus disembunyikan) |

Akun: `arkavilai` (Ajudan), `raflyakbar` (Ajudan), `leonardus` (Driver), `alam` (Driver).
Password disimpan sebagai **SHA-256 hash**, bukan plaintext.

### Jejak "siapa" (tag)

- Setiap data punya tag **penginput** (chip biru + ikon orang + nama). Nama ini
  **tidak berubah** walau diedit orang lain — server mempertahankan `by` asli.
- Kalau pernah diedit, muncul chip kuning **"diedit oleh <nama> · <waktu>"**.
- Riwayat Kas punya filter **"Tampilkan input"** untuk menyaring per-orang.
- Di server, 3 kolom mendukung ini: `by_name` (penginput asli), `edited_by`,
  `edited_ts`. `ts` (stempel urutan) sengaja **tidak** diubah saat edit supaya
  tidak memicu perang last-write-wins antar device; sinkron pakai `edited_ts`.

## Deploy

```bash
git add -A
git commit -m "..."
git push          # GitHub Pages otomatis rilis ~1 menit
```

## Backup & restore

```bash
bash backup-gdrive.sh
```

Menulis ke `G:\My Drive\VPS ATLAS\DASHBOARD-KAS`:
- salinan *deployable* (index/v2/fix/sw/manifest/ikon) di root folder,
- snapshot bertimestamp `backup-YYYYMMDD_HHMMSS/` (frontend + backend + DB + infra),
- `dashboard-kas-backup-<stamp>.zip` untuk restore cepat.

DB di-snapshot lewat `sqlite3 .backup` (aman walau server sedang jalan).
Kredensial tunnel (`atlas-kas.json`) **tidak** ikut di-backup.

Restore:
1. **Frontend** — `git clone dashboard-kas.bundle dashboard-kas`, lalu push ke GitHub.
2. **Backend** — salin folder `backend/` ke `D:\ATLAS-DATA\dashboard-kas-backend`.
3. **DB** — hentikan server, ganti `db.sqlite3` dengan salinan backup.
4. **Infra** — `cloudflared-atlas-kas.yml` → `C:\Users\arka\.cloudflared\`,
   `programdata-atlas-kas.yml` → `C:\ProgramData\atlas-kas\`.

## Kepatuhan desain (aturan ATLAS)

Semua halaman wajib lolos detektor resmi, target `[]`:

```bash
cd C:/Users/arka/ATLAS-SKILLS/skills/atlas-design/atlas-impeccable
node scripts/detect.mjs --json D:/ATLAS-DATA/dashboard-kas/index.html
```

Aturan yang berlaku: tidak ada font terlarang (roboto/inter/geist/…), rasio
ukuran teks ≥ 2.0, padding wajib ada (tidak cramped), jangan gabung border tipis
+ shadow lebar, ikon harus SVG (bukan emoji/glyph), warna lewat token, kontras
teks ≥ 4.5:1 (WCAG AA), tanpa overflow di lebar 390px.

---

Dibuat: 10 Okt 2026 · Terakhir diperbarui: 11 Okt 2026
