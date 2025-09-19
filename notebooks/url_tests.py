#!/usr/bin/env python3
import argparse, json, subprocess, sys
from pathlib import Path

import requests

DEFAULTS = {
    "host": "localhost",

    # nginx front door (kept around, but DB UIs tested by port now)
    "http_port": 80,

    # direct service ports
    "api_port": 8000,
    "redpanda_admin_port": 9644,
    "redpanda_console_port": 8085,
    "spark_master_ui": 9090,
    "spark_worker_ui": 9091,
    "spark_history_ui": 18080,
    "jupyter_port": 8889,
    "minio_api_port": 9000,
    "minio_console_port": 9001,

    # pgweb & pgadmin via ports (NOT via /src or /dest)
    "pgweb_src_port": None,   # will try tfvars first, then docker
    "pgweb_dst_port": None,
    "pgadmin_port": None,

    # feature toggles
    "enable_minio": False,
}

def load_json(path: Path):
    try:
        with path.open() as f:
            return json.load(f)
    except Exception:
        return {}

def maybe_int(v, default=None):
    try:
        return int(v)
    except Exception:
        return default

def merge_from_tfvars(d, tfvars):
    # root-level ports
    d["http_port"] = maybe_int(tfvars.get("http_port", d["http_port"]), d["http_port"])
    d["api_port"] = maybe_int(tfvars.get("api_port", d["api_port"]), d["api_port"])
    d["redpanda_console_port"] = maybe_int(tfvars.get("console_port", d["redpanda_console_port"]), d["redpanda_console_port"])
    d["redpanda_admin_port"] = maybe_int(tfvars.get("admin_port", d["redpanda_admin_port"]), d["redpanda_admin_port"])

    # pgweb / pgadmin by port
    d["pgweb_src_port"] = maybe_int(tfvars.get("pgweb_src_port", d["pgweb_src_port"]), d["pgweb_src_port"])
    d["pgweb_dst_port"] = maybe_int(tfvars.get("pgweb_dst_port", d["pgweb_dst_port"]), d["pgweb_dst_port"])
    d["pgadmin_port"]   = maybe_int(tfvars.get("pgadmin_port", d["pgadmin_port"]), d["pgadmin_port"])

    # Spark & friends from env map (strings)
    env = tfvars.get("env", {})
    d["spark_master_ui"]  = maybe_int(env.get("SPARK_MASTER_UI_PORT", d["spark_master_ui"]), d["spark_master_ui"])
    d["spark_worker_ui"]  = maybe_int(env.get("SPARK_WORKER_UI_BASE", d["spark_worker_ui"]), d["spark_worker_ui"])
    d["spark_history_ui"] = maybe_int(env.get("SPARK_HISTORY_PORT", d["spark_history_ui"]), d["spark_history_ui"])
    d["jupyter_port"]     = maybe_int(env.get("JUPYTER_PORT", d["jupyter_port"]), d["jupyter_port"])

    # MinIO
    d["enable_minio"] = str(env.get("ENABLE_MINIO", "false")).lower() == "true"
    d["minio_api_port"] = maybe_int(env.get("MINIO_API_PORT", d["minio_api_port"]), d["minio_api_port"])
    d["minio_console_port"] = maybe_int(env.get("MINIO_CONSOLE_PORT", d["minio_console_port"]), d["minio_console_port"])
    return d

def docker_discover_port(container: str, internal_port: int):
    """Return host port for container's tcp port, or None."""
    try:
        out = subprocess.run(
            ["docker", "port", container, f"{internal_port}/tcp"],
            check=True, capture_output=True, text=True
        ).stdout.strip()
        # examples: "0.0.0.0:8082" or "[::]:8082"
        if not out:
            return None
        last = out.splitlines()[-1].split(":")[-1]
        return int(last)
    except Exception:
        return None

def collect_urls(cfg, stack_dir: Path, include_tf_outputs: bool, include_nginx_root: bool):
    host = cfg["host"]
    urls = []

    # (optional) nginx root (not /src or /dest anymore)
    if include_nginx_root:
        if cfg["http_port"] in (80, None):
            urls.append(("Nginx root", f"http://{host}", {}))
        else:
            urls.append(("Nginx root", f"http://{host}:{cfg['http_port']}", {}))

    # direct services
    urls += [
        ("FastAPI (direct)",        f"http://{host}:{cfg['api_port']}", {}),
        ("Redpanda Admin /ready",   f"http://{host}:{cfg['redpanda_admin_port']}/v1/status/ready", {"expect_json": {"status": "ready"}}),
        ("Redpanda Console",        f"http://{host}:{cfg['redpanda_console_port']}", {}),
        ("Spark Master UI",         f"http://{host}:{cfg['spark_master_ui']}", {}),
        ("Spark Worker-1 UI",       f"http://{host}:{cfg['spark_worker_ui']}", {}),
        ("Spark History UI",        f"http://{host}:{cfg['spark_history_ui']}", {}),
        ("JupyterLab",              f"http://{host}:{cfg['jupyter_port']}", {}),
    ]

    # pgweb & pgadmin by port
    if cfg.get("pgweb_src_port"):
        urls.append(("pgweb (source)", f"http://{host}:{cfg['pgweb_src_port']}", {}))
    if cfg.get("pgweb_dst_port"):
        urls.append(("pgweb (destination)", f"http://{host}:{cfg['pgweb_dst_port']}", {}))
    if cfg.get("pgadmin_port"):
        urls.append(("pgAdmin (direct)", f"http://{host}:{cfg['pgadmin_port']}", {}))

    if cfg.get("enable_minio"):
        urls += [
            ("MinIO API (S3)",      f"http://{host}:{cfg['minio_api_port']}", {}),
            ("MinIO Console",       f"http://{host}:{cfg['minio_console_port']}", {}),
        ]

    # Terraform outputs that look like URLs
    if include_tf_outputs:
        try:
            out = subprocess.run(
                ["terraform", "-chdir=" + str(stack_dir), "output", "-json"],
                check=True, capture_output=True, text=True
            )
            j = json.loads(out.stdout or "{}")
            for k, v in j.items():
                val = v.get("value") if isinstance(v, dict) else v
                if isinstance(val, str) and ("http://" in val or "https://" in val):
                    urls.append((f"TF output: {k}", val, {}))
        except Exception:
            pass

    # de-dupe by URL
    seen, uniq = set(), []
    for name, u, opts in urls:
        if u not in seen:
            uniq.append((name, u, opts))
            seen.add(u)
    return uniq

def check(url, opts, timeout):
    try:
        r = requests.get(url, timeout=timeout, allow_redirects=True, verify=False)
        ok, msg = r.status_code < 400, f"{r.status_code}"
        if opts.get("expect_json"):
            want = opts["expect_json"]
            try:
                data = r.json()
                ok_json = all(data.get(k) == v for k, v in want.items())
                ok = ok and ok_json
                msg += f", json {want} {'ok' if ok_json else 'mismatch'}"
            except Exception as e:
                ok = False
                msg += f", json parse error: {e}"
        return ok, msg
    except requests.exceptions.RequestException as e:
        return False, f"ERR {type(e).__name__}: {e}"

def main():
    ap = argparse.ArgumentParser(description="Probe all service URLs in the stack (ports for DB UIs).")
    ap.add_argument("--host", default=DEFAULTS["host"])
    ap.add_argument("--stack-dir", default="infra/docker")
    ap.add_argument("--tfvars", help="Path to env.auto.tfvars.json (optional)")
    ap.add_argument("--no-tf-outputs", action="store_true", help="Skip terraform output -json")
    ap.add_argument("--no-nginx-root", action="store_true", help="Skip testing http://host[:port]")
    ap.add_argument("--timeout", type=float, default=5.0)
    ap.add_argument("--docker-discover", action="store_true",
                    help="If pgweb/pgadmin ports missing, try docker port pgweb_src 8081/tcp etc.")
    args = ap.parse_args()

    cfg = DEFAULTS.copy()
    cfg["host"] = args.host

    if args.tfvars:
        cfg = merge_from_tfvars(cfg, load_json(Path(args.tfvars)))

    # Optional docker discovery for pgweb/pgadmin if not in tfvars
    if args.docker_discover:
        if not cfg.get("pgweb_src_port"):
            cfg["pgweb_src_port"] = docker_discover_port("pgweb_src", 8081)
        if not cfg.get("pgweb_dst_port"):
            cfg["pgweb_dst_port"] = docker_discover_port("pgweb_dst", 8081)
        if not cfg.get("pgadmin_port"):
            cfg["pgadmin_port"] = docker_discover_port("pgadmin", 80)

        # Also discover Redpanda Console if needed
        if not cfg.get("redpanda_console_port"):
            cfg["redpanda_console_port"] = docker_discover_port("redpanda-console", 8080)
        if not cfg.get("redpanda_admin_port"):
            cfg["redpanda_admin_port"] = docker_discover_port("redpanda", 9644)

    urls = collect_urls(
        cfg,
        Path(args.stack_dir),
        include_tf_outputs=(not args.no_tf_outputs),
        include_nginx_root=(not args.no_nginx_root),
    )

    print(f"\nTesting {len(urls)} endpoints (timeout={args.timeout}s):\n")
    width = max(len(name) for name, _, _ in urls) + 2
    failures = 0

    for name, url, opts in urls:
        ok, msg = check(url, opts, args.timeout)
        status = "PASS" if ok else "FAIL"
        if not ok:
            failures += 1
        print(f"{status:<5} {name:<{width}} {url}    {msg}")

    print("\nDone.")
    if failures:
        print(f"{failures} endpoint(s) failed.")
        sys.exit(1)

if __name__ == "__main__":
    # quiet SSL warnings for local HTTP
    requests.packages.urllib3.disable_warnings()  # type: ignore
    main()


