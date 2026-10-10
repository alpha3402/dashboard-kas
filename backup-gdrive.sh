#!/usr/bin/env bash
# Backup Dashboard Kas (ATLAS) -> GDrive "VPS ATLAS"/DASHBOARD-KAS
# Idempoten: menimpa berkas deployable dgn nama sama; snapshot ber-timestamp.
# Catatan path: bash/msys pakai /d/.. /g/..  ; git & python (program Windows)
# harus pakai D:/.. G:/..  -> dikonversi dgn cygpath -w.
set -uo pipefail

SRC_FE="/d/ATLAS-DATA/dashboard-kas"
SRC_BE="/d/ATLAS-DATA/dashboard-kas-backend"
DEST="/g/My Drive/VPS ATLAS/DASHBOARD-KAS"
STAMP=$(date +%Y%m%d_%H%M%S)
STAGE="/tmp/dk-backup-$STAMP"
LOG=/tmp/gdrive_backup.log
: > "$LOG"

# python yg punya modul lengkap (untuk sqlite3/zipfile)
PY='/c/Users/arka/AppData/Local/hermes/hermes-agent/venv/Scripts/python.exe'
[ -x "$PY" ] || PY='/c/Users/arka/AppData/Local/Programs/Python/Python314/python'
w(){ cygpath -w "$1"; }   # msys -> windows

say(){ echo "$@" | tee -a "$LOG"; }
mkdir -p "$DEST" "$STAGE" "$STAGE/backend" "$STAGE/infra" || { echo "GAGAL buat dir"; exit 1; }

say "== 1. Frontend: salinan deployable (konvensi flat) =="
for f in index.html v2.html fix.html sw.js manifest.json README.md \
         icon-180.png icon-192.png icon-512.png icon-maskable.png; do
  [ -f "$SRC_FE/$f" ] && cp -f "$SRC_FE/$f" "$DEST/$f" && say "   ok $f"
done

say "== 2. Susun snapshot di staging lokal =="
for f in "$SRC_FE"/*.html "$SRC_FE"/*.js "$SRC_FE"/*.json "$SRC_FE"/*.png "$SRC_FE"/*.md "$SRC_FE"/*.sh; do
  [ -e "$f" ] && cp -f "$f" "$STAGE/" 2>/dev/null
done
say "   frontend: $(ls -1 "$STAGE"/*.html "$STAGE"/*.js "$STAGE"/*.json "$STAGE"/*.png "$STAGE"/*.md "$STAGE"/*.sh 2>/dev/null | wc -l) berkas"

# git bundle (riwayat penuh, bisa di-clone) — pakai path Windows
if [ -d "$SRC_FE/.git" ]; then
  if timeout 180 git -C "$(w "$SRC_FE")" bundle create "$(w "$STAGE/dashboard-kas.bundle")" --all >>"$LOG" 2>&1; then
    say "   git bundle ok ($(du -h "$STAGE/dashboard-kas.bundle" | cut -f1))"
  else
    say "   !! git bundle gagal (lihat log)"
  fi
  timeout 60 git -C "$(w "$SRC_FE")" log -1 --format='%H | %ad | %s' --date=iso \
    > "$STAGE/GIT-LAST-COMMIT.txt" 2>/dev/null
fi

# backend (kecuali __pycache__, db, log, browser-profile)
if [ -d "$SRC_BE" ]; then
  find "$SRC_BE" -maxdepth 1 -type f \( -name '*.py' -o -name '*.ps1' -o -name '*.md' \) \
    -exec cp -f {} "$STAGE/backend/" \; 2>/dev/null
  for d in deploy-atlas _arsip; do
    [ -d "$SRC_BE/$d" ] && cp -rf "$SRC_BE/$d" "$STAGE/backend/" 2>/dev/null
  done
  say "   backend: $(find "$STAGE/backend" -type f | wc -l) berkas"
fi

# DB: snapshot konsisten via sqlite3 API (aman walau server sedang jalan + WAL)
"$PY" - "$(w "$SRC_BE/db.sqlite3")" "$(w "$STAGE/backend/db.sqlite3")" >>"$LOG" 2>&1 <<'PYEOF'
import sqlite3, sys, os
src, dst = sys.argv[1], sys.argv[2]
if not os.path.exists(src):
    print('DB_BACKUP: SKIP (tidak ada)'); sys.exit(0)
try:
    s = sqlite3.connect('file:%s?mode=ro' % src.replace('\\', '/'), uri=True)
    d = sqlite3.connect(dst)
    with d: s.backup(d)
    s.close(); d.close()
    print('DB_BACKUP: ok %d bytes' % os.path.getsize(dst))
except Exception as e:
    print('DB_BACKUP: GAGAL %s' % e)
PYEOF
DBL=$(grep -a '^DB_BACKUP:' "$LOG" | tail -1)
say "   ${DBL:-DB_BACKUP: (tak ada output)}"

# infra config (tanpa kredensial JSON)
for pair in "/c/Users/arka/.cloudflared/atlas-kas.yml:cloudflared-atlas-kas.yml" \
            "/c/ProgramData/atlas-kas/atlas-kas.yml:programdata-atlas-kas.yml"; do
  src="${pair%%:*}"; nm="${pair##*:}"
  [ -f "$src" ] && cp -f "$src" "$STAGE/infra/$nm" && say "   ok infra/$nm"
done

# manifest + isi DB
{
  echo "DASHBOARD KAS — BACKUP SNAPSHOT"
  echo "Waktu    : $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "Host     : $(hostname)  user=${USER:-arka}"
  echo "Sumber   : $SRC_FE + $SRC_BE"
  echo "Live app : https://alpha3402.github.io/dashboard-kas/"
  echo "API      : https://kas.atlastechcompany.web.id"
  echo
  echo "--- Isi snapshot ---"
  ( cd "$STAGE" && find . -type f -printf '%-44P %10s bytes\n' | sort )
  echo
  echo "--- Cara restore ---"
  echo "Frontend : git clone dashboard-kas.bundle dashboard-kas   (lalu git push ke GitHub)"
  echo "Backend  : copy backend/ -> D:\\ATLAS-DATA\\dashboard-kas-backend"
  echo "DB       : ganti db.sqlite3 dengan backend/db.sqlite3  (server berhenti dulu)"
  echo "Infra    : cloudflared-atlas-kas.yml -> C:\\Users\\arka\\.cloudflared\\"
  echo "           programdata-atlas-kas.yml -> C:\\ProgramData\\atlas-kas\\"
  echo "           (kredensial tunnel .json TIDAK di-backup — ambil dari Cloudflare)"
  echo
  echo "--- Isi database (ringkas) ---"
} > "$STAGE/MANIFEST.txt"
"$PY" - "$(w "$STAGE/backend/db.sqlite3")" >>"$STAGE/MANIFEST.txt" 2>/dev/null <<'PYEOF'
import sqlite3, sys, os
p = sys.argv[1]
if not os.path.exists(p): print('  (tidak ada db)'); sys.exit()
c = sqlite3.connect(p)
for (t,) in c.execute("select name from sqlite_master where type='table' order by name"):
    try: n = c.execute('select count(*) from "%s"' % t).fetchone()[0]
    except Exception: n = '?'
    print('  %-14s %s baris' % (t, n))
PYEOF

say "== 3. Upload ke GDrive =="
rm -rf "$DEST/backup-$STAMP"
if cp -rf "$STAGE" "$DEST/backup-$STAMP"; then say "   ok $DEST/backup-$STAMP"; else say "   !! copy gagal"; fi

# zip satu berkas utk restore cepat (tanpa infra/, via python zipfile)
"$PY" - "$(w "$STAGE")" "$(w "$DEST/dashboard-kas-backup-$STAMP.zip")" >>"$LOG" 2>&1 <<'PYEOF'
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
n = 0
try:
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(stage):
            if os.path.basename(root) == 'infra':
                dirs[:] = []; continue
            for f in files:
                p = os.path.join(root, f)
                z.write(p, os.path.relpath(p, stage)); n += 1
    print('ZIP: ok %d berkas, %d bytes' % (n, os.path.getsize(out)))
except Exception as e:
    print('ZIP: GAGAL', e)
PYEOF
say "   $(grep -a '^ZIP:' "$LOG" | tail -1)"

say ""
say "== RINGKASAN =="
say "Tujuan   : $DEST"
say "Snapshot : $(find "$STAGE" -type f | wc -l) berkas, $(du -sh "$STAGE" | cut -f1)"
say "Isi folder DASHBOARD-KAS: $(du -sh "$DEST" | cut -f1)"
say "Daftar   :"
ls -1 "$DEST" | sed 's/^/   /' | tee -a "$LOG"
rm -rf "$STAGE"
