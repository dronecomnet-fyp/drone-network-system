# Which runbook do I read?

Thirteen runbooks accumulated over the project and five have been
archived. This is the index so nobody has to guess.

## Start here

| I want to... | Read |
|--------------|------|
| Know where the project is and what to do next | `docs/where_you_are.html` |
| **Bring a node to a known good state, or fix an inconsistent one** | **`docs/node_reset.html`** |
| Work out why a node has no mesh | Run `sudo bash tools/dtn_doctor.sh` on it |

## Building hardware from nothing

| Task | Runbook |
|------|---------|
| Blank SD card to a working node | `deploy/windows_pi_bringup.html` |
| Second node and the DTN mesh | `deploy/windows_mesh_bringup.html` |
| DRONE_S, with the MAVLink gateway | `deploy/windows_drone_s_bringup.html` |
| Flash and bench-test an aux module | `firmware/aux1/windows_bringup.html` |
| Build the front panel: switch, beep, lamps | `docs/node_front_panel.html` |

## Apps and the ground station

| Task | Runbook |
|------|---------|
| Build and install the phone apps | `docs/phone_apps_bringup.html` |
| Build and run the GCC | `gcc_app/windows_gcc_bringup.html` |
| GCC drone control bring-up | `gcc_app/windows_drone_control.html` |

## Checking and measuring

| Task | Runbook |
|------|---------|
| Verify a rebuilt node | `deploy/VERIFY.md` |
| Verify the mission layer end to end | `deploy/mission_layer_check.html` |
| Capture evidence for the report | `docs/testing_evidence_plan.html` |

## Archived

`deploy/archived_runbooks/` holds five one-off update procedures, one per
round of changes. They are superseded by `docs/node_reset.html`, because
`setup_node.sh` is re-runnable and one procedure now covers every case
they covered separately. See the README in that folder.

## The rule that keeps this list short

**There is no such thing as an update runbook any more.** Updating a node
and fixing a broken node are the same operation: pull, run
`setup_node.sh`, reboot, verify. Write a new runbook only for something
genuinely new, such as hardware that did not exist before.
