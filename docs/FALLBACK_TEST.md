# Testing LoRa fallback without chasing ghosts

How to prove a downed drone still reports itself, and how to tell the
three silent failure modes apart when it does not.

Written after a test that produced nothing and looked like a broken
feature. It was not: every reason the beacon can fail to appear is
invisible, so the procedure matters more than usual.

## What has to happen, in order

Five separate things. If any one fails the Degraded tab stays empty, and
none of them announce themselves.

1. The **aux module on the target node** notices the Pi has stopped
   sending heartbeats, and enters FALLBACK.
2. It **transmits** a beacon over LoRa, then every 30 seconds after.
3. A **different node** receives it. A node cannot hear itself.
4. That node's aux bridge **logs it and stores it** in `lora_events`.
5. The GCC is joined to a node that **has that record**, either the
   receiver or one it has synced with since.

## Before you start

**Battery B must already be connected and the module already running on
it.** If the module has been living on USB power from the Pi and the
battery only goes on at the moment of the test, cutting the Pi power
cycles the module. It reboots, and after a reboot it waits
`FIRST_PING_GRACE_MS`, sixty seconds, for a first heartbeat that will
never come, before it even starts the fifteen second dead-Pi countdown.

**Do not reboot or cleanly shut down the target node in the ninety
seconds before the test.** A clean shutdown tells the module the silence
is expected and it suppresses fallback for `SHUTDOWN_GRACE_MS`. That is
deliberate, so that switching a node off does not raise a fleet alarm,
but it will also swallow your test. If you have just rebooted, wait two
minutes.

**Pull the power. Do not use `poweroff`.** A hard cut is what you are
simulating, and it is also the only way to be certain no shutdown notice
was sent.

## The procedure

Two nodes at minimum. Target is the one that will "fail"; receiver is the
one that must hear it.

**On the receiver, before anything**, start watching:

```
tail -f ~/rescue-mesh/backend/audit.log | grep --line-buffered -a FALLBACK
```

Leave that running where you can see it.

**On the target**, confirm the module is alive and on its own battery,
then pull the Pi's power cable.

**Now wait.** The timings are:

| From | Event |
|------|-------|
| 0 s | Pi power cut, heartbeats stop |
| 15 s | Module declares the Pi dead and enters FALLBACK |
| 15 s | First beacon transmitted immediately |
| every 30 s | Further beacons |

So **the first line should appear about fifteen seconds in**. Give it
ninety seconds before concluding anything, and longer if the module had
to reboot.

## Reading the result

**A line appears:**

```
FALLBACK_BEACON | node=DRONE_A | rssi=-46 | msg_id=6e80... | carrying=two adults on a roof
```

The radio path works. `rssi` around -40 to -60 is a strong bench signal.
Now check the app side:

```
grep -ac FALLBACK ~/rescue-mesh/backend/audit.log
curl -sk https://127.0.0.1:8443/lora-events -H "X-API-Key: $KEY" | head -c 300
```

If the log has beacons but `lora_events` is empty, the fault is between
the bridge and the database, which is a real bug worth reporting.

**Nothing appears at all**, in order of likelihood:

| Check | How |
|-------|-----|
| Was a shutdown notice armed? | Did you reboot the target in the last 90 s? Wait and repeat |
| Did the module reboot when power was cut? | It was on USB, not on Battery B. Connect the battery first and repeat |
| Is Battery B actually powering it? | Measure it. A flat cell looks identical to a working one from here |
| Is the receiver's aux module connected? | `grep -a AUX_CONNECT audit.log \| tail -1` on the receiver |
| Are both modules on the current firmware? | `cd firmware/aux1 && pio run -t upload`, both of them |
| Is the LoRa radio wired and initialised? | Check the receiver logged `LORA_RX` at any point ever |

Transmit power is deliberately at the library minimum pending TRCSL
confirmation, so range is short. For a first test put the two modules on
the same bench, a metre apart. Do not start at fifty metres.

## Reading old evidence

`audit.log` is not rotated, so it holds every beacon since the node was
built. **Check the dates.** A test that produced nothing today looks
identical to a successful one if you read a line from last week and do
not notice the timestamp.

```
grep -a FALLBACK_BEACON ~/rescue-mesh/backend/audit.log | tail -5
date
```

Two things to know when comparing against old entries:

- Beacons received before the LoRa event log was added are in the audit
  log and in `node_health`, but **not** in `lora_events`, so the Degraded
  tab cannot show them. That is correct, not a bug.
- `/health` only reports a node as degraded while beacons are recent,
  within `FALLBACK_EXPIRY`, which is 120 seconds. A week-old beacon is
  correctly ignored. The Degraded tab is about now.

## What the tab shows when it works

The downed node, its last beacon age, signal strength, which node heard
it, the battery it reported, and the last victim message it was carrying.
A blinking marker on the map at its last known position. After power is
restored it moves to Recovered, automatically, once the module has seen
three consecutive heartbeats.
