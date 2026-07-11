"""
http_app.py — HTTP-only captive portal (port 8080 or 8000)

Sole purpose: trigger the OS "sign in to network" popup and show victims
instructions + the HTTPS link where they can actually send a message.

NO data endpoints. NO API keys accepted. NO message submission.
Everything functional lives on the HTTPS app (api.py, port 8443).
"""

import os
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, PlainTextResponse

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

HTTPS_HOST = os.getenv("HTTPS_HOST", "10.42.0.1")
HTTPS_PORT = os.getenv("HTTPS_PORT", "8443")
HTTPS_BASE = f"https://{HTTPS_HOST}:{HTTPS_PORT}"

# ---------------------------------------------------------------------------
# Captive portal instruction page — shown inside the OS popup
# ---------------------------------------------------------------------------
PORTAL_INSTRUCTIONS_HTML = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Emergency Rescue Network</title>
    <style>
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #f3f4f6;
            color: #111827;
            padding: 16px;
        }}
        .card {{
            background: #ffffff;
            border-radius: 14px;
            padding: 22px 18px;
            box-shadow: 0 6px 18px rgba(0,0,0,0.10);
            max-width: 520px;
            margin: 16px auto;
        }}
        .badge {{
            display: inline-block;
            background: #dc2626;
            color: #fff;
            font-size: 11px;
            font-weight: 700;
            letter-spacing: .06em;
            padding: 3px 8px;
            border-radius: 99px;
            margin-bottom: 10px;
        }}
        h1 {{
            font-size: 20px;
            color: #b91c1c;
            margin-bottom: 6px;
        }}
        .sub {{
            font-size: 14px;
            color: #374151;
            margin-bottom: 18px;
            line-height: 1.5;
        }}
        .steps {{
            background: #f9fafb;
            border: 1px solid #e5e7eb;
            border-radius: 10px;
            padding: 14px 16px;
            margin-bottom: 18px;
        }}
        .steps h2 {{
            font-size: 13px;
            font-weight: 700;
            color: #6b7280;
            letter-spacing: .05em;
            margin-bottom: 10px;
            text-transform: uppercase;
        }}
        .step {{
            display: flex;
            align-items: flex-start;
            gap: 10px;
            margin-bottom: 10px;
            font-size: 14px;
            line-height: 1.45;
        }}
        .step:last-child {{ margin-bottom: 0; }}
        .num {{
            background: #dc2626;
            color: #fff;
            font-size: 12px;
            font-weight: 700;
            width: 22px;
            height: 22px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-shrink: 0;
            margin-top: 1px;
        }}
        .link-box {{
            background: #eff6ff;
            border: 2px solid #3b82f6;
            border-radius: 10px;
            padding: 14px 16px;
            text-align: center;
            margin-bottom: 14px;
        }}
        .link-box p {{
            font-size: 13px;
            color: #1e40af;
            margin-bottom: 8px;
        }}
        .link-box a {{
            font-size: 18px;
            font-weight: 700;
            color: #1d4ed8;
            text-decoration: none;
            word-break: break-all;
        }}
        .warn {{
            font-size: 12px;
            color: #6b7280;
            text-align: center;
            line-height: 1.5;
        }}
        .warn strong {{ color: #374151; }}
    </style>
</head>
<body>
    <div class="card">
        <div class="badge">🚨 EMERGENCY NETWORK</div>
        <h1>Rescue Drone Connected</h1>
        <p class="sub">
            You are connected to an emergency rescue drone hotspot.
            Follow the steps below to send your message to the rescue team.
        </p>

        <div class="steps">
            <h2>How to send a message</h2>
            <div class="step">
                <div class="num">1</div>
                <div>Tap the secure link below to open the message portal in your browser.</div>
            </div>
            <div class="step">
                <div class="num">2</div>
                <div>Your browser may show a <strong>security warning</strong> about the certificate — tap <em>"Advanced" → "Proceed"</em> to continue. This is expected on a local drone network.</div>
            </div>
            <div class="step">
                <div class="num">3</div>
                <div>Type your situation, injuries, or needs in the form. Optionally share your GPS location.</div>
            </div>
            <div class="step">
                <div class="num">4</div>
                <div>Tap <strong>SEND MESSAGE</strong>. The drone will relay it to the rescue team.</div>
            </div>
            <div class="step">
                <div class="num">5</div>
                <div>Note your <strong>Session ID</strong> shown after sending — the rescue team will use it to confirm they found you.</div>
            </div>
        </div>

        <div class="link-box">
            <p>Open this link in your browser to send a message:</p>
            <a href="{HTTPS_BASE}" target="_blank" rel="noopener noreferrer">{HTTPS_BASE}</a>
        </div>

        <p class="warn">
            <strong>Stay calm and stay put.</strong><br>
            Keep your phone connected to this Wi-Fi network.<br>
            The drone will relay your message automatically.
        </p>
    </div>
</body>
</html>
"""


def portal_page() -> HTMLResponse:
    return HTMLResponse(content=PORTAL_INSTRUCTIONS_HTML)


# ---------------------------------------------------------------------------
# OS captive portal probe endpoints
# Each OS probes a specific URL to detect captive portals.
# Returning unexpected content (instead of the exact "internet OK" response)
# triggers the "sign in to network" popup.
# ---------------------------------------------------------------------------

@app.get("/")
def root():
    """Default — shown when victim manually opens the hotspot IP."""
    return portal_page()


@app.get("/generate_204")
def android_probe():
    """
    Android probes this and expects HTTP 204 when internet is free.
    Returning HTTP 200 with content signals a captive portal exists
    → triggers the 'Sign in to DRONE_X network' notification.
    """
    return portal_page()


@app.get("/hotspot-detect.html")
def ios_probe():
    """
    iOS probes this and expects the exact Apple success string.
    Returning anything else triggers the captive portal popup on iPhones.
    """
    return portal_page()


@app.get("/ncsi.txt")
def windows_probe():
    """
    Windows probes this and expects the exact string 'Microsoft NCSI'.
    Returning anything else triggers the Windows network notification.
    """
    return PlainTextResponse(content="Rescue Network Portal", status_code=200)


@app.get("/connecttest.txt")
def windows_probe_alt():
    """Windows 10/11 alternate probe endpoint."""
    return PlainTextResponse(content="Rescue Network Portal", status_code=200)


@app.get("/captive-portal/status")
def captive_status():
    """Signal that a captive portal is active (returns 204 as expected by some detectors)."""
    return HTMLResponse(content="", status_code=204)


@app.get("/{path:path}")
def catch_all(path: str, request: Request):
    """
    Catch-all: any unknown path returns the instruction portal.
    This handles OS probes we haven't explicitly listed above.
    """
    return portal_page()


if __name__ == "__main__":
    import uvicorn

    host = os.getenv("HTTP_HOST", "0.0.0.0")
    port = int(os.getenv("HTTP_PORT", "8080"))

    print(f"[*] Starting HTTP captive portal on {host}:{port}")
    print(f"[*] Victims will be directed to {HTTPS_BASE}")
    uvicorn.run(app, host=host, port=port)
