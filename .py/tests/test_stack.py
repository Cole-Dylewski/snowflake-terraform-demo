# tests/test_stack.py
# Run:  pip install pytest requests
#       pytest -q -s

import json
import os
import socket
import subprocess
from typing import Dict, Any

import os, json, subprocess
from pathlib import Path

import pytest
import requests


HOST = os.environ.get("STACK_HOST", "localhost")
TIMEOUT = float(os.environ.get("STACK_TEST_TIMEOUT", "3.0"))

HTTP_ENDPOINTS = [
    ("Nginx root",              f"http://{HOST}"),
    ("FastAPI (direct)",        f"http://{HOST}:8000"),
    ("Redpanda Console",        f"http://{HOST}:8085"),
    ("Spark Master UI",         f"http://{HOST}:9090"),
    ("Spark Worker-1 UI",       f"http://{HOST}:9091"),
    ("Spark History UI",        f"http://{HOST}:18080"),
    ("JupyterLab",              f"http://{HOST}:8889"),
    ("pgAdmin",                 f"http://{HOST}:8080"),
    ("pgweb src",               f"http://{HOST}:8081"),
    ("pgweb dst",               f"http://{HOST}:8082"),
]

TCP_ENDPOINTS = [
    ("Kafka (external TCP)", HOST, 19092),
    ("Postgres src",         HOST, 5433),
    ("Postgres dst",         HOST, 5434),
]

# Containers we expect to expose a Docker health status
CONTAINERS_WITH_HEALTH = [
    "redpanda",
    "redpanda-console",
    "spark-history",
]


def _curl_json(url: str) -> requests.Response:
    return requests.get(url, timeout=TIMEOUT)


def _curl_ok(url: str) -> requests.Response:
    # consider 2xx/3xx as pass (similar to the bash checker)
    r = requests.get(url, timeout=TIMEOUT, allow_redirects=True)
    assert r.status_code < 400, f"{url} returned HTTP {r.status_code}"
    return r


def _check_tcp(host: str, port: int) -> None:
    with socket.create_connection((host, port), timeout=TIMEOUT):
        pass


def _have_cmd(cmd: str) -> bool:
    return subprocess.run(["bash", "-lc", f"command -v {cmd} >/dev/null 2>&1"], check=False).returncode == 0


TF_DIR = os.environ.get(
    "TF_DIR",
    str(Path(__file__).resolve().parents[2] / "infra/docker")  # repo-root/infra/docker
)

def _terraform_outputs():
    if subprocess.run(["bash","-lc","command -v terraform >/dev/null 2>&1"]).returncode:
        return {}
    proc = subprocess.run(
        ["bash", "-lc", f"terraform -chdir='{TF_DIR}' output -json"],
        capture_output=True, text=True
    )
    if proc.returncode != 0:
        return {}
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {}
    return {k: v["value"] for k, v in data.items() if isinstance(v, dict) and "value" in v}


@pytest.mark.parametrize("name,url", HTTP_ENDPOINTS)
def test_http_endpoints(name: str, url: str):
    _curl_ok(url)


def test_redpanda_admin_ready():
    # The base admin URL may 404; the readiness endpoint must be 200 with {"status":"ready"}.
    url = f"http://{HOST}:9644/v1/status/ready"
    r = _curl_json(url)
    assert r.status_code == 200, f"{url} returned {r.status_code}"
    data = r.json()
    assert data.get("status") == "ready", f"Unexpected JSON at {url}: {data}"


@pytest.mark.parametrize("name,host,port", TCP_ENDPOINTS)
def test_tcp_sockets_open(name: str, host: str, port: int):
    _check_tcp(host, port)


@pytest.mark.skipif(not _have_cmd("docker"), reason="docker not available")
@pytest.mark.parametrize("container", CONTAINERS_WITH_HEALTH)
def test_container_health_is_healthy(container: str):
    # Read .State.Health.Status; if absent, fail with useful message.
    proc = subprocess.run(
        ["bash", "-lc", f"docker inspect --format '{{{{json .State}}}}' {container}"],
        capture_output=True, text=True
    )
    assert proc.returncode == 0, f"docker inspect failed for {container}: {proc.stderr}"
    try:
        state = json.loads(proc.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Cannot parse docker inspect JSON for {container}: {proc.stdout}")
    health = (state.get("Health") or {}).get("Status")
    assert health is not None, f"{container} has no Health status (define a healthcheck in Terraform?)"
    assert health == "healthy", f"{container} health is '{health}'"


@pytest.mark.skipif(not _have_cmd("terraform"), reason="terraform not available")
def test_terraform_output_urls_reachable():
    """
    Validate URLs emitted by TF outputs. For admin URL, hit the readiness endpoint.
    """
    outs = _terraform_outputs()
    assert outs, "No terraform outputs found (did you run 'terraform apply'?)"

    # Map output keys to the URL we should actually check.
    checks = []
    if "app_url" in outs:
        checks.append(("TF app_url", outs["app_url"]))
    if "pgadmin_url" in outs:
        checks.append(("TF pgadmin_url", outs["pgadmin_url"]))
    if "pgweb_src_url" in outs:
        checks.append(("TF pgweb_src_url", outs["pgweb_src_url"]))
    if "pgweb_dst_url" in outs:
        checks.append(("TF pgweb_dst_url", outs["pgweb_dst_url"]))
    if "redpanda_console_url" in outs:
        checks.append(("TF redpanda_console_url", outs["redpanda_console_url"]))
    if "redpanda_admin_url" in outs:
        # Append readiness path for the admin API output
        base = outs["redpanda_admin_url"].rstrip("/")
        checks.append(("TF redpanda_admin_url (/ready)", f"{base}/v1/status/ready"))

    # Run the checks
    assert checks, f"No relevant URL outputs present in: {list(outs.keys())}"
    for name, url in checks:
        r = requests.get(url, timeout=TIMEOUT, allow_redirects=True)
        assert r.status_code < 400, f"{name} {url} returned {r.status_code}"


# --- Optional: small smoke job to generate a Spark event (if pyspark present) ---

@pytest.mark.skipif(
    not os.environ.get("RUN_SPARK_SMOKE"),
    reason="set RUN_SPARK_SMOKE=1 to run the Spark job"
)
def test_spark_smoke_job_generates_event_log():
    """
    Optional: submits a tiny Spark job to the remote master to help populate event logs.
    Requires pyspark in the test environment (pip install pyspark).
    """
    try:
        from pyspark.sql import SparkSession
    except Exception as e:
        pytest.skip(f"pyspark not available: {e}")

    spark = (
        SparkSession.builder
        .master(f"spark://{HOST}:7077")
        .appName("hist-check")
        .config("spark.eventLog.enabled", "true")
        .config("spark.eventLog.dir", "file:/opt/bitnami/spark/tmp/spark-events")
        .getOrCreate()
    )
    try:
        df = spark.range(10000).selectExpr("sum(id) as s")
        row = df.collect()[0]
        assert row["s"] == 49995000
    finally:
        spark.stop()
