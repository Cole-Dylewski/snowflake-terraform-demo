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


@asynccontextmanager
async def lifespan(app: FastAPI):
    await startup()
    try:
        yield
    finally:
        await shutdown()

app = FastAPI(
    title="Demo FastAPI", 
    # root_path="/api/v2",
    version="0.1.0",
    lifespan=lifespan,
    # docs_url="/docs", #if ENV.lower() == 'dev' else None, 
    # redoc_url="/redocs" #if ENV.lower() == 'dev' else None
)

def get_public_ip() -> str:
    """Return the caller’s public IPv4 address."""
    return requests.get("https://api.ipify.org").text

async def startup() -> None:
    
    ip_address = get_public_ip()
    print("Startup complete. IP Address:", ip_address)

async def shutdown() -> None:
    print("Shutdown complete")

@app.get("/", response_class=HTMLResponse)
async def get_info(request: Request):
    ip = request.client.host
    id = socket.gethostname()
    port = request.url.port
    server_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    content = f"""
    <html>
    <head>
        <title>Demo App FastAPI</title>
        <style>
            body {{
                font-family: Arial, sans-serif;
                background: linear-gradient(135deg, #4a90e2, #FFFFFF);
                color: #333;
                margin: 0;
                padding: 0;
                display: flex;
                flex-direction: column;
                align-items: center;
                justify-content: center;
                height: 100vh;
                text-align: center;
            }}
            .container {{
                background-color: #fff;
                padding: 30px;
                border-radius: 12px;
                box-shadow: 0 4px 15px rgba(0, 0, 0, 0.2);
                max-width: 500px;
                width: 90%;
                margin: 20px;
            }}
            h1 {{
                color: #4a90e2;
                margin-bottom: 10px;
            }}
            p {{
                margin: 5px 0;
            }}
            .dynamic-time {{
                font-size: 18px;
                color: #e94e77;
                margin-top: 15px;
            }}
            .link {{
                font-weight: bold;
                color: #4a90e2;
                text-decoration: none;
                transition: color 0.3s ease;
            }}
            .link:hover {{
                color: #e94e77;
                text-decoration: underline;
            }}
            .footer {{
                margin-top: 20px;
                font-size: 12px;
                color: #777;
            }}
        </style>
        <script>
            function updateCurrentTime() {{
                const currentTimeElement = document.getElementById("currentTime");
                const currentTime = new Date().toLocaleTimeString();
                currentTimeElement.textContent = `Current Time: ${{currentTime}}`;
            }}
            setInterval(updateCurrentTime, 1000);
            updateCurrentTime();
        </script>
    </head>
    <body>
        <div class="container">
            <h1>FastAPI Current Time</h1>
            <p>backend updates</p>
            <p><a href="http://localhost/docs" class="link" target="_blank">Go to FastAPI Documentation</a></p>
            <p>IP: {ip}</p>
            <p>Docker Container ID: {id}</p>
            <p>Port: {port}</p>
            <p>Server Time: {server_time}</p>
            <p id="currentTime" class="dynamic-time">Current Time: Loading...</p>
        </div>
        <div class="footer">
            <p>&copy; 2024 Cole Dylewski. All rights reserved.</p>
        </div>
    </body>
    </html>
    """

    return content

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