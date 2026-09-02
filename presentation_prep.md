# FYP Final Evaluation Preparation Guide

This guide breaks down your presentation slide-by-slide, maps the concepts directly to your codebase, and anticipates questions the evaluators might ask (along with how to answer them using your actual code).

## 1. System Architecture & Components (Slide 6 & 12)

### Backend (`backend/`)
The backend is written in **Python (FastAPI)** and uses **SQLite** for lightweight, serverless database management.
*   **`http_app.py` (Victim Portal / Captive Portal):** Serves over HTTP (Port 80). When a victim connects to the drone's Wi-Fi, this portal is automatically shown. It has validation and rate-limiting but no complex authentication, making it frictionless for victims.
*   **`api.py`:** The authenticated API for Rescue Teams and Ground Control, served over HTTPS (Port 8443).
*   **Database (`models.py`):** Uses standard SQLite. It stores messages, personnel details, and node health.

### Frontend Apps
All apps are built with **Flutter** (Dart), allowing a single codebase for multiple platforms.
*   **`gcc_app/` (Ground Control Center):** Used by command. Features offline maps (likely cached or pre-loaded), node health monitoring, and mission planning. It communicates primarily with the secure `api.py`.
*   **`rescue_app/` (Rescue Personnel App):** Used by ground teams. Features offline PIN-based authentication. Teams can claim victim requests and file reports. It syncs securely via the drone's mesh.
*   **`emergency_app/` (Emergency App):** A simplified app for victims (if they have it installed, though the captive portal is the primary method).
*   **`website/`:** Contains the frontend code for the captive portal, built with HTML/JS (Vite).

---

## 2. Feature Implementation Details (How things actually work in code)

### The Sync Engine & Mesh Network (Slide 11)
**Files to know:** `backend/sync_engine.py`, `backend/sync_daemon.py`
*   **How it works:** The `sync_daemon.py` constantly broadcasts "I'm here" beacons. When nodes get close, they exchange what they have.
*   **Conflict Resolution:** In `sync_engine.py`, when a new record arrives, the code checks the `status`. If a message is marked as `CLAIMED` by one node and `NEW` by another, `CLAIMED` wins. If *both* are claimed, the one with the *earlier* `claimed_at` timestamp wins.
*   **Security (Slide 9):** Every record synced is HMAC-signed (`crypto_keys.py`). This prevents forged data in transit. 

### The Dual-Unit Architecture & Fallback (Slide 10)
**Files to know:** `backend/aux_bridge.py`, `firmware/aux/src/main.cpp`
*   **How it works:** The main Raspberry Pi (Main Compute Unit) communicates with the ESP32-C3 (Auxiliary Module) over serial connection (115200 baud).
*   **The "Heartbeat":** In `aux_bridge.py`, the Pi sends a `ping` every 5 seconds (`AUX_PING_INTERVAL`).
*   **The Fallback Logic:** The ESP32-C3 quietly watches. If 15 seconds pass without a `ping` from the Pi, the ESP32 assumes the Pi has died (power loss, software crash). It then automatically takes over, broadcasting LoRa fallback beacons and BLE discovery signals so the drone isn't lost.

---

## 3. Potential Questions from Evaluators & How to Answer

### Q1: "You mentioned there is no central server. How do you prevent data conflicts if two rescue workers claim the same victim at the same time on different drones?"
**How to answer:** Mention the **Conflict Resolution rules** in your `sync_engine.py`. Explain that all records are timestamped. If two `CLAIMED` statuses sync, the engine looks at the `claimed_at` time. The earlier claim wins, and the database updates automatically across the mesh.

### Q2: "How does the captive portal work without internet?"
**How to answer:** Explain that the drone broadcasts an open Wi-Fi AP. When a phone connects, the phone's OS tries to ping a known URL (like a connectivity check). The Raspberry Pi captures this DNS request and redirects it to `http_app.py` running on Port 80, automatically opening the HTML form. No internet is required.

### Q3: "What happens if the main Raspberry Pi gets destroyed or loses power?"
**How to answer:** Refer to your **Dual-Unit Architecture** (`aux_bridge.py`). Explain the 5-second serial ping. If the ESP32-C3 auxiliary module misses pings for 15 seconds, it triggers the fallback mode. Because it runs on a separate, highly efficient battery circuit, it will outlast the main unit and continue broadcasting the drone's location via LoRa.

### Q4: "How do you ensure the security of the mesh if someone tries to inject fake rescue requests?"
**How to answer:** Mention your **Security Model**. The captive portal only accepts strictly validated HTTP input with rate-limiting to prevent spam. For inter-drone sync, every record is cryptographically signed (`HMAC`) using keys derived from a master secret (`crypto_keys.py`). If a signature doesn't match, the `sync_engine.py` rejects the record.

### Q5: "Why did you build the fallback recovery three times?" (Referring to Slide 8)
**How to answer:** Explain the iterative learning process. Originally, the fallback was one-way (if the node crashed, it stayed dead). You realized that if the Pi just rebooted temporarily, it was permanently locked out. You had to rewrite the logic in `aux_bridge.py` and the firmware to allow the node to gracefully hand power *back* to the main unit if it recovered.

### Q6: "Why use both LoRa and Wi-Fi/BLE?"
**How to answer:** Wi-Fi is high-bandwidth but short-range (used for the mesh sync and user portal). LoRa is low-bandwidth but extremely long-range (used for the fallback beacons and critical state summaries). This dual-radio approach ensures stability.

---

## Pro-Tips for the Presentation
*   **If they ask to see code:** Have `backend/sync_engine.py` and `backend/aux_bridge.py` open in your IDE. These are the most impressive parts of your logic.
*   **Emphasize "Built, not just designed":** Point out that you actually passed 243 automated tests and ran bench tests on the firmware. It's a proven system.
