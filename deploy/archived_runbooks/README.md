# Archived runbooks

These were one-off update procedures, each written for a single round of
changes: "roll out the rescuer location feature", "roll out the DEGRADED
fixes", "roll out the LoRa log". They were correct when written.

They are archived because they are no longer the way to update a node,
and having five of them made it genuinely hard to know which to follow.

**Use `docs/node_reset.html` instead.** `setup_node.sh` is re-runnable and
brings a node to a known state whatever it was in before, so a single
procedure now covers every case these documents covered separately.

Kept rather than deleted because they record what each round changed and
in what order, which is useful history for the report.

| File | Was for |
|------|---------|
| `node_update_locations.html` | The rescuer location table (M7d) |
| `windows_node_update.html` | The M7 mission-layer app features |
| `windows_degraded_fix.html` | The DEGRADED-forever fix and fallback recovery |
| `windows_full_rollout.html` | A combined status and rollout page |
| `node_update_lora_log.html` | The LoRa event log and portal options |

Its diagnostic content, in particular the ladder for a blank sync log,
now lives in `tools/dtn_doctor.sh`, which checks the same chain
automatically.
