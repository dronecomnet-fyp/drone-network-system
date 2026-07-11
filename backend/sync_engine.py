import requests
import sqlite3
import os
import hmac
import hashlib
import logging

DB_FILE = "drone_mesh.db"
SYNC_API_KEY = os.getenv("SYNC_API_KEY", "rk_team_a_alpha")
INTER_NODE_SECRET = os.getenv("INTER_NODE_SECRET", "mesh_change_me")
NODE_SHARED_SECRET = os.getenv("NODE_SHARED_SECRET", "mesh_signing_change_me")
SYNC_SCHEME = os.getenv("SYNC_SCHEME", "http")
SYNC_PORT = int(os.getenv("SYNC_PORT", "8000"))
SYNC_VERIFY_TLS = os.getenv("SYNC_VERIFY_TLS", "false").strip().lower() in {"1", "true", "yes", "on"}
SYNC_CA_CERT = os.getenv("SYNC_CA_CERT", "drone_ca.crt")
SYNC_CLIENT_CERT = os.getenv("SYNC_CLIENT_CERT", "")
SYNC_CLIENT_KEY = os.getenv("SYNC_CLIENT_KEY", "")

AUDIT_LOG_FILE = os.getenv("AUDIT_LOG_FILE", "audit.log")
audit_logger = logging.getLogger("audit")
if not audit_logger.handlers:
    audit_logger.setLevel(logging.INFO)
    audit_handler = logging.FileHandler(AUDIT_LOG_FILE)
    audit_handler.setFormatter(logging.Formatter("%(asctime)s | %(levelname)s | %(message)s"))
    audit_logger.addHandler(audit_handler)


def sign_message(msg_id, content, timestamp):
    payload = f"{msg_id}:{content}:{timestamp}"
    return hmac.new(NODE_SHARED_SECRET.encode(), payload.encode(), hashlib.sha256).hexdigest()


def verify_message_signature(msg_id, content, timestamp, signature):
    expected = sign_message(msg_id, content, timestamp)
    return hmac.compare_digest(expected, signature)

def sync_with_peer(peer_ip):
    print(f"[*] Attempting to sync with peer at {peer_ip}...")
    audit_logger.info(f"SYNC_START | peer={peer_ip}")
    try:
        peer_url = f"{SYNC_SCHEME}://{peer_ip}:{SYNC_PORT}/messages"
        verify_tls = SYNC_CA_CERT if SYNC_VERIFY_TLS else False
        client_cert = (SYNC_CLIENT_CERT, SYNC_CLIENT_KEY) if SYNC_CLIENT_CERT and SYNC_CLIENT_KEY else None

        # 1. Fetch messages from the other drone's API
        response = requests.get(
            peer_url,
            headers={
                "X-Node-Auth": INTER_NODE_SECRET,
            },
            verify=verify_tls,
            cert=client_cert,
            timeout=5
        )
        
        if response.status_code == 200:
            peer_messages = response.json()
            print(f"[+] Downloaded {len(peer_messages)} messages from peer.")
            
            # 2. Save them to our local database with status precedence
            conn = sqlite3.connect(DB_FILE)
            c = conn.cursor()
            
            new_count = 0
            updated_count = 0
            
            for msg in peer_messages:
                try:
                    msg_id = msg['msg_id']
                    peer_status = msg.get('status', 'NEW')
                    peer_signature = msg.get('signature', '')

                    if not verify_message_signature(
                        msg_id,
                        msg['content'],
                        msg['timestamp'],
                        peer_signature
                    ):
                        print(f"[-] Rejected unsigned or tampered message {msg_id} from {peer_ip}")
                        audit_logger.warning(f"SYNC_REJECT | peer={peer_ip} | msg_id={msg_id} | reason=bad_signature")
                        continue
                    
                    # Check if message already exists
                    c.execute("SELECT status FROM messages WHERE msg_id = ?", (msg_id,))
                    existing = c.fetchone()
                    
                    if existing:
                        # Message exists: apply status precedence
                        local_status = existing[0]
                        
                        # CLAIMED status takes precedence over NEW
                        if local_status == 'CLAIMED':
                            # Keep local CLAIMED status
                            pass
                        elif peer_status == 'CLAIMED':
                            # Update to CLAIMED from peer
                            c.execute('''
                                UPDATE messages SET status = 'CLAIMED' WHERE msg_id = ?
                            ''', (msg_id,))
                            updated_count += 1
                        # else: both NEW, no need to update
                    else:
                        # New message from peer: insert with all fields
                        c.execute('''
                            INSERT INTO messages 
                            (
                                msg_id, content, location, timestamp, origin_node,
                                synced, status, signature, is_encrypted, encryption_alg, encryption_kid
                            )
                            VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
                        ''', (msg_id, msg['content'], msg['location'], msg['timestamp'], 
                            msg['origin_node'], peer_status, peer_signature,
                            1 if msg.get('is_encrypted', 0) else 0,
                            msg.get('encryption_alg', ''),
                            msg.get('encryption_kid', ''),
                        ))
                        new_count += 1
                        
                except (sqlite3.IntegrityError, KeyError) as e:
                    print(f"[-] Error processing message {msg.get('msg_id', 'UNKNOWN')}: {e}")
                    continue
            
            conn.commit()
            conn.close()
            print(f"[+] Sync complete. Added {new_count} new messages, updated {updated_count} message statuses.")
            audit_logger.info(
                f"SYNC_OK | peer={peer_ip} | imported={new_count} | updated={updated_count}"
            )
        else:
            print(f"[-] Peer returned status code {response.status_code}")
            audit_logger.warning(f"SYNC_FAIL | peer={peer_ip} | status_code={response.status_code}")
            
    except requests.exceptions.RequestException as e:
        print(f"[-] Failed to connect to peer {peer_ip}: {e}")
        audit_logger.warning(f"SYNC_FAIL | peer={peer_ip} | reason=request_exception")

if __name__ == "__main__":
    # If run manually, try to sync with the standard gateway IP
    sync_with_peer("10.42.0.1")
