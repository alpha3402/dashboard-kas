"""Backend dashboard kas & kegiatan — FastAPI + SQLite lokal."""
import os, json, time, hashlib, secrets
from datetime import datetime
from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import sqlite3
from pydantic import BaseModel
from typing import Optional

DB_PATH = os.environ.get("DASHBOARD_DB") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "db.sqlite3")
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

# ---------- USERS (password SHA-256, sama dgn client lama) ----------
USERS = [
    {"un": "arkavilai",   "pw": "arka02060091", "role": "Ajudan"},
    {"un": "raflyakbar",  "pw": "rafly123",     "role": "Ajudan"},
    {"un": "leonardus",   "pw": "leo123",       "role": "Driver"},
    {"un": "alam",        "pw": "alam123",      "role": "Driver"},
]

def sha(s): return hashlib.sha256(s.encode()).hexdigest()

def db():
    c = sqlite3.connect(DB_PATH)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    return c

def init():
    c = db()
    c.executescript("""
    CREATE TABLE IF NOT EXISTS kegiatan (
      id TEXT PRIMARY KEY, nama TEXT, tanggal TEXT, waktu TEXT,
      lokasi TEXT, desc TEXT, by TEXT, role TEXT, ts INTEGER
    );
    CREATE TABLE IF NOT EXISTS transaksi (
      id TEXT PRIMARY KEY, tanggal TEXT, jenis TEXT, nominal INTEGER,
      kat TEXT, catatan TEXT, by TEXT, role TEXT, ts INTEGER
    );
    CREATE TABLE IF NOT EXISTS foto (
      id TEXT PRIMARY KEY, keg_id TEXT, data TEXT, ts INTEGER,
      FOREIGN KEY(keg_id) REFERENCES kegiatan(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS f_keg ON foto(keg_id);
    """)
    c.commit(); c.close()

init()

# ---------- AUTH ----------
class Creds(BaseModel):
    un: str
    pw: str

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

def verify(r: Request):
    tok = r.headers.get("x-auth")
    if not tok:
        raise HTTPException(401, "no token")
    try:
        un, role = tok.split("|", 1)
    except Exception:
        raise HTTPException(401, "bad token")
    u = [x for x in USERS if x["un"] == un]
    if not u:
        raise HTTPException(401, "unknown user")
    if role != u[0]["role"]:
        raise HTTPException(401, "bad role")
    return {"un": un, "role": role}

def admin_only(user):
    if user["role"] != "Ajudan":
        raise HTTPException(403, "hanya ajudan")

# ---------- MODELS ----------
class Keg(BaseModel):
    id: str; nama: str; tanggal: str; waktu: Optional[str] = ""
    lokasi: Optional[str] = ""; desc: Optional[str] = ""
class Tx(BaseModel):
    id: str; tanggal: str; jenis: str; nominal: int
    kat: str; catatan: Optional[str] = ""
class Foto(BaseModel):
    id: str; keg_id: str; data: str

# ---------- ENDPOINTS ----------
@app.post("/login")
def login(creds: Creds):
    u = [x for x in USERS if x["un"] == creds.un and sha(x["pw"]) == sha(creds.pw)]
    if not u:
        raise HTTPException(401, "username/password salah")
    return {"un": u[0]["un"], "role": u[0]["role"], "token": f"{u[0]['un']}|{u[0]['role']}"}

@app.get("/me")
def me(user=Depends(verify)):
    return user

@app.get("/data")
def all_data(user=Depends(verify)):
    c = db()
    keg = [dict(r) for r in c.execute("SELECT * FROM kegiatan ORDER BY tanggal, ts")]
    tx  = [dict(r) for r in c.execute("SELECT * FROM transaksi ORDER BY tanggal, ts")]
    fot = [dict(r) for r in c.execute("SELECT id, keg_id, ts FROM foto")]
    c.close()
    return {"kegiatan": keg, "transaksi": tx, "fotos": fot}

@app.post("/keg")
def add_keg(k: Keg, user=Depends(verify)):
    admin_only(user)
    c = db()
    c.execute("INSERT OR REPLACE INTO kegiatan (id,nama,tanggal,waktu,lokasi,`desc`,`by`,role,ts) VALUES (?,?,?,?,?,?,?,?,?)",
              (k.id, k.nama, k.tanggal, k.waktu or "", k.lokasi or "", k.desc or "", user["un"], user["role"], int(time.time()*1000)))
    c.commit(); c.close()
    return {"ok": True}

@app.delete("/keg/{kid}")
def del_keg(kid: str, user=Depends(verify)):
    admin_only(user)
    c = db()
    c.execute("DELETE FROM foto WHERE keg_id=?", (kid,))
    c.execute("DELETE FROM kegiatan WHERE id=?", (kid,))
    c.commit(); c.close()
    return {"ok": True}

@app.post("/tx")
def add_tx(t: Tx, user=Depends(verify)):
    admin_only(user)
    c = db()
    c.execute("INSERT OR REPLACE INTO transaksi (id,tanggal,jenis,nominal,kat,catatan,`by`,role,ts) VALUES (?,?,?,?,?,?,?,?,?)",
              (t.id, t.tanggal, t.jenis, t.nominal, t.kat, t.catatan or "", user["un"], user["role"], int(time.time()*1000)))
    c.commit(); c.close()
    return {"ok": True}

@app.delete("/tx/{tid}")
def del_tx(tid: str, user=Depends(verify)):
    admin_only(user)
    c = db()
    c.execute("DELETE FROM transaksi WHERE id=?", (tid,))
    c.commit(); c.close()
    return {"ok": True}

@app.post("/foto")
def add_foto(f: Foto, user=Depends(verify)):
    c = db()
    c.execute("INSERT OR REPLACE INTO foto (id,keg_id,data,ts) VALUES (?,?,?,?)",
              (f.id, f.keg_id, f.data, int(time.time()*1000)))
    c.commit(); c.close()
    return {"ok": True}

@app.delete("/foto/{fid}")
def del_foto(fid: str, user=Depends(verify)):
    admin_only(user)
    c = db()
    c.execute("DELETE FROM foto WHERE id=?", (fid,))
    c.commit(); c.close()
    return {"ok": True}

@app.get("/foto/{fid}")
def get_foto(fid: str, user=Depends(verify)):
    c = db()
    r = c.execute("SELECT data FROM foto WHERE id=?", (fid,)).fetchone()
    c.close()
    if not r:
        raise HTTPException(404, "not found")
    return JSONResponse({"data": r["data"]})

@app.post("/sync")
def sync(payload: dict, user=Depends(verify)):
    """Bulk sync up: client kirim semua data localnya"""
    admin_only(user)
    c = db()
    for k in payload.get("kegiatan", []):
        c.execute("INSERT OR REPLACE INTO kegiatan (id,nama,tanggal,waktu,lokasi,`desc`,`by`,role,ts) VALUES (?,?,?,?,?,?,?,?,?)",
                  (k["id"], k.get("nama",""), k.get("tanggal",""), k.get("waktu",""), k.get("lokasi",""), k.get("desc",""), k.get("by",""), k.get("role",""), k.get("ts",0)))
    for t in payload.get("transaksi", []):
        c.execute("INSERT OR REPLACE INTO transaksi (id,tanggal,jenis,nominal,kat,catatan,`by`,role,ts) VALUES (?,?,?,?,?,?,?,?,?)",
                  (t["id"], t["tanggal"], t["jenis"], t["nominal"], t["kat"], t.get("catatan",""), t.get("by",""), t.get("role",""), t.get("ts",0)))
    c.commit(); c.close()
    return {"ok": True}

@app.post("/reset")
def reset(user=Depends(verify)):
    admin_only(user)
    c = db()
    for t in ("kegiatan","transaksi","foto"):
        c.execute(f"DELETE FROM {t}")
    c.commit(); c.close()
    return {"ok": True}
