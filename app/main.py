# app/main.py
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse

# import utility libraries
from datetime import datetime, timedelta
from contextlib import asynccontextmanager
import socket
import pandas as pd
from pydantic import BaseModel
import os, json
import requests
from _utils.snowflake.snowpark import SnowparkClient
from snowflake.snowpark import types as spt



app = FastAPI()


@app.get("/")
def read_root():
    return {"message": "Hello, World"}

@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.get("/snow/health")
def snow_health():
    sp = SnowparkClient.from_env()
    with sp:
        ctx = sp.current()
        top5 = sp.run("select 1 as ok", collect=True)
    return {"ctx": ctx, "ok": bool(top5)}