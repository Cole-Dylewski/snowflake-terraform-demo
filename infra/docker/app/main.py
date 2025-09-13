from fastapi import FastAPI
import os, psycopg2
from psycopg2.extras import RealDictCursor

app = FastAPI()

SRC_DSN = os.environ["DATABASE_URL_SRC"]
DST_DSN = os.environ["DATABASE_URL_DST"]

def get_conn(dsn):
    return psycopg2.connect(dsn, cursor_factory=RealDictCursor)

@app.get("/healthz")
def health():
    return {"status": "ok"}

@app.get("/counts")
def counts():
    with get_conn(SRC_DSN) as s, get_conn(DST_DSN) as d:
        with s.cursor() as cs, d.cursor() as cd:
            cs.execute("SELECT COUNT(*) AS n FROM widgets;")
            cd.execute("SELECT COUNT(*) AS n FROM widgets;")
            return {"src": cs.fetchone()["n"], "dst": cd.fetchone()["n"]}

@app.post("/transfer")
def transfer():
    with get_conn(SRC_DSN) as s, get_conn(DST_DSN) as d:
        with s.cursor() as cs, d.cursor() as cd:
            cs.execute("SELECT id, name FROM widgets ORDER BY id;")
            rows = cs.fetchall()
            for r in rows:
                cd.execute(
                    """
                    INSERT INTO widgets (id, name)
                    VALUES (%s, %s)
                    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
                    """,
                    (r["id"], r["name"])
                )
    return {"migrated": len(rows)}
