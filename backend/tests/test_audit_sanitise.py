"""
The audit log must stay one line per event, in plain text, even when a
line quotes data the system did not author.

Two real problems behind this:

  1. LOG INJECTION. Several audit lines quote content that arrived from
     outside: a victim's message, the last message a LoRa fallback beacon
     was carrying. A newline in that content starts a new line in the log,
     which an attacker can shape to look like a genuine entry. The LoRa
     path is the sharp end, because anyone can transmit on a radio.

  2. BINARY CONTENT. Control bytes make grep call the file binary and
     print nothing but "binary file matches". That is how an operator ends
     up believing a healthy fleet is broken, which happened during the
     August 2026 field session.

Run with: .venv/bin/pytest tests/test_audit_sanitise.py -q
"""

import importlib
import logging
import os


def _fresh_logger(tmp_path):
    """A logger writing to a temp file.

    Reloading the modules is not enough on its own: logging.getLogger
    returns a process-wide singleton, so the handler created by an earlier
    import survives a reload and keeps writing to the old path. The
    handlers have to be removed explicitly.
    """
    lg = logging.getLogger("audit")
    for h in list(lg.handlers):
        lg.removeHandler(h)
        h.close()

    os.environ["AUDIT_LOG_FILE"] = str(tmp_path / "audit.log")
    import config
    importlib.reload(config)
    import audit
    importlib.reload(audit)
    return audit.get_audit_logger(), tmp_path / "audit.log"


FORGERY = ("help\n2026-01-01 00:00:00,000 | INFO | LOGIN_OK | user=attacker")


def test_a_newline_in_radio_content_cannot_forge_a_log_entry(tmp_path):
    log, path = _fresh_logger(tmp_path)
    log.warning(f"FALLBACK_BEACON | node=DRONE_B | last_msg={FORGERY}")
    lines = [l for l in path.read_text().splitlines() if l.strip()]
    assert len(lines) == 1, (
        "one event produced more than one line: the injected newline "
        "escaped and an attacker can write their own audit entries")
    assert "\\x0a" in lines[0], "the newline should be visibly escaped"


def test_control_bytes_never_reach_the_file(tmp_path):
    """Otherwise grep reports 'binary file matches' and shows nothing."""
    log, path = _fresh_logger(tmp_path)
    log.info("LORA_RX | payload=\x00\x1b[31m\x07binary\x00junk")
    raw = path.read_bytes()
    for bad in (b"\x00", b"\x1b", b"\x07"):
        assert bad not in raw, f"raw {bad!r} in the audit log makes it binary"


def test_an_over_long_line_is_truncated_not_dropped(tmp_path):
    """A flood of junk must not fill the SD card, and must not silently
    lose the event either."""
    import audit
    log, path = _fresh_logger(tmp_path)
    log.info("MESSAGE_CREATE | content=" + ("A" * 9000))
    line = path.read_text().strip()
    assert "truncated" in line
    assert len(line) < audit.MAX_LINE + 200
    assert "MESSAGE_CREATE" in line, "the event itself must survive"


def test_ordinary_lines_are_completely_unchanged(tmp_path):
    """The sanitiser must be invisible in normal operation."""
    log, path = _fresh_logger(tmp_path)
    normal = "SYNC_OK | peer=DRONE_B | table=lora_events | imported=0"
    log.info(normal)
    assert path.read_text().strip().endswith(normal)
