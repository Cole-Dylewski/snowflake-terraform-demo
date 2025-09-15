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
import boto3

from khepri_utils.utils import sql


app = FastAPI()


@app.get("/")
def read_root():
    return {"message": "Hello, World"}

@app.get("/health")
def health_check():
    return {"status": "ok"}
