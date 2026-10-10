# Deploy backend Dashboard Kas ke mesin ATLAS (Linux)

Tujuan: pindahkan backend dari `arka-pc` (Windows) ke mesin `atlas` (Linux),
supaya backend selalu hidup dan tidak bergantung pada PC yang kadang mati.

## Prasyarat (di mesin atlas)

| Item | Nilai |
|---|---|
| Host | `atlas` (Tailscale `100.126.226.37`, `atlas.tail56e0cb.ts.net`) |
| OS | Linux (Debian/Ubuntu) |
| Akses | root |
| Domain | `kas.atlastechcompany.web.id` → tunnel `atlas-kas` |
| Port | `8000` |

## Langkah

### 1. Salin kredensial tunnel dari arka-pc

```bash
# di arka-pc:
scp ~/.cloudflared/78ac83f2-f90e-4836-bf74-4cad2ed1123d.json root@atlas:/root/.cloudflared/atlas-kas.json
```

Kalau `~/.cloudflared/atlas-kas.json` tidak ada di arka-pc, ambil dari
file `78ac83f2-...json` di `C:\Users\arka\.cloudflared\`.

### 2. Jalankan setup

```bash
scp deploy-atlas/setup.sh root@atlas:/tmp/
ssh root@atlas 'bash /tmp/setup.sh'
```

Setup membuat:
- `/opt/dashboard-kas-backend/` — aplikasi + venv
- `systemd: dashboard-kas.service` — FastAPI di `127.0.0.1:8000`
- `systemd: dashboard-kas-tunnel.service` — cloudflared `atlas-kas`
- keduanya `enable` → auto-start saat boot

### 3. Pindahkan data yang sudah ada (opsional)

```bash
scp D:/ATLAS-DATA/dashboard-kas-backend/db.sqlite3 root@atlas:/opt/dashboard-kas-backend/db.sqlite3
ssh root@atlas 'systemctl restart dashboard-kas'
```

### 4. Matikan backend lama di arka-pc

```powershell
Stop-ScheduledTask -TaskName 'ATLAS-KAS-BACKEND'
Disable-ScheduledTask -TaskName 'ATLAS-KAS-BACKEND'
Stop-Process -Name cloudflared -Force   # HATI-HATI: matikan HANYA proses atlas-kas
```

Frontend tidak perlu diubah — tetap `https://kas.atlastechcompany.web.id`.

## Verifikasi

```bash
curl -s https://kas.atlastechcompany.web.id/data -H 'x-auth: arkavilai|Ajudan'
# → {"kegiatan":[],"transaksi":[...],"fotos":[]}
```

## Catatan

- Tunnel `atlas-kas` tidak boleh punya DUA konektor aktif (arka-pc + atlas)
  bersamaan. Kalau perlu pindah, matikan yang lama dulu.
- Kalau mesin atlas di balik NAT, tunnel keluar tetap jalan (koneksi outbound).
