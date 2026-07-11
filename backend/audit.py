"""
audit.py: shared audit logger. Every daemon (api, portal, sync, aux bridge)
appends to the same audit log file; append-mode file handles from multiple
processes are safe for line-oriented logging on Linux.

Kept from Phase 1 unchanged in spirit (file 09: KEEP the audit log); file 09
section 2 adds login attempts and, later, MAVLink gateway events as sources.
"""

import logging

import config

_LOGGER_NAME = "audit"


def get_audit_logger() -> logging.Logger:
    logger = logging.getLogger(_LOGGER_NAME)
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        handler = logging.FileHandler(config.AUDIT_LOG_FILE)
        handler.setFormatter(logging.Formatter("%(asctime)s | %(levelname)s | %(message)s"))
        logger.addHandler(handler)
    return logger
