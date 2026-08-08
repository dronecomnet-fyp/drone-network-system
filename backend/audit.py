"""
audit.py: shared audit logger. Every daemon (api, portal, sync, aux bridge)
appends to the same audit log file; append-mode file handles from multiple
processes are safe for line-oriented logging on Linux.

Kept from Phase 1 unchanged in spirit (file 09: KEEP the audit log); file 09
section 2 adds login attempts and, later, MAVLink gateway events as sources.

SANITISING, and why it is not optional. Several audit lines quote data the
system did not author: a victim's message, the last message carried by a
LoRa fallback beacon, a sender name. Two things go wrong if that is written
through unmodified.

  1. A newline in that data starts a NEW LINE in the audit log, which an
     attacker can shape to look like a genuine entry. An audit log that can
     be written to by the thing it is auditing is not an audit log. This
     matters most on the LoRa path, where the content arrives over a radio
     anyone can transmit on.

  2. Control bytes make the file "binary" to ordinary tools. grep then
     answers "binary file matches" and prints nothing, which is exactly how
     an operator ends up believing a healthy fleet is broken. That happened.

Both are fixed here rather than at each call site, because there are dozens
of call sites and the next one to be added would have the same problem.
"""

import logging

import config

_LOGGER_NAME = "audit"

# Long enough for any legitimate line, short enough that a flood of junk
# cannot fill the card as quickly.
MAX_LINE = 2000


def _escape_control(text: str) -> str:
    """Replace anything that is not printable text with a visible escape.

    Newlines and carriage returns included, deliberately: preserving them
    would defeat the point, since one log entry must stay one line.
    """
    out = []
    for ch in text:
        code = ord(ch)
        if code < 32 or code == 127:
            out.append("\\x%02x" % code)
        else:
            out.append(ch)
    return "".join(out)


class _SanitiseFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        message = _escape_control(record.getMessage())
        if len(message) > MAX_LINE:
            message = message[:MAX_LINE] + "...[truncated]"
        # Replace the message and clear args: getMessage() has already
        # applied them, and leaving them would format twice.
        record.msg = message
        record.args = ()
        return True


def get_audit_logger() -> logging.Logger:
    logger = logging.getLogger(_LOGGER_NAME)
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        # backslashreplace so a byte sequence that cannot be encoded is
        # written as visible text rather than raw bytes. The filter above
        # handles control characters; this is the second line of defence
        # for anything that reaches the handler anyway.
        handler = logging.FileHandler(
            config.AUDIT_LOG_FILE, encoding="utf-8", errors="backslashreplace")
        handler.setFormatter(logging.Formatter("%(asctime)s | %(levelname)s | %(message)s"))
        handler.addFilter(_SanitiseFilter())
        logger.addHandler(handler)
    return logger
