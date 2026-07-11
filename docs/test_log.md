# Test log

Every integration test (file 07, T1 to T9) gets a dated entry here:
date, test id, pass/fail, who ran it, evidence file (photo, screen
recording, sqlite dump, or log excerpt). Bench tests from
firmware/TESTS.md and deploy/VERIFY.md runs are logged here too.

Format, one row per run:

| Date | Test | Result | Ran by | Evidence |
|------|------|--------|--------|----------|
| YYYY-MM-DD | T1 node soak (drone_a) | PASS/FAIL | name | path or link |

No entries yet: hardware acceptance runs happen after the foundation
packages (01, 02, 03) are deployed to the rebuilt Pis.
