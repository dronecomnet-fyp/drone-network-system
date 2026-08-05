# Node front panel: power switch, beep and lights

**Building one? Follow `docs/node_front_panel.html` instead.** It is the same
content as a browsable runbook with a pin-header diagram, which is easier to
work from with a soldering iron in hand. This file is the reference.

What to buy, where to solder it, and what each light means. This is field
backlog #1, scoped by the operator to a power switch plus a beep and lights
at startup. Everything here lives on the Raspberry Pi.

## Why the Pi and not the aux module

The aux module was the first instinct, because it survives the Pi dying and
could therefore beep during LoRa fallback. Two reasons it is not:

1. **There is no free pin.** Every XIAO ESP32-C3 signal pin is already
   allocated (CHANGES.md item 10, where LoRa MISO had to move to the last
   spare). Adding a buzzer would mean giving up a LoRa line.
2. The operator chose the Pi.

**The consequence, stated plainly:** the panel cannot indicate anything
once the Pi is dead, which is exactly the fallback case. A failed node goes
dark locally. The aux module still tells the rest of the fleet over LoRa,
so the GCC sees it, but nobody standing next to that drone will. This was
accepted deliberately rather than overlooked.

## Parts

| Part | Spec | Notes |
|------|------|-------|
| Power switch | SPST latching rocker or toggle, **5 A** rating | Must carry the whole node. Do not use a 1 A signal switch |
| Buzzer | **Active** 3.3 V, roughly 12 mm | Active means it makes its own tone from a HIGH level. A PASSIVE buzzer needs a PWM tone and will stay silent with this code |
| LED green | 3 mm or 5 mm | READY |
| LED amber | 3 mm or 5 mm | MESH |
| Resistors | 2 x 220 to 330 ohm | One per LED. Do not omit these |
| Momentary button | small tactile, normally open | OPTIONAL but recommended, see the SD card warning |
| Wire | 22 AWG stranded | |

A buzzer over roughly 25 mA needs a transistor rather than a direct GPIO
connection. Most small 3.3 V active buzzers are well under that; check the
datasheet before wiring it straight to a pin.

## Wiring, BCM numbering

These four pins are free on every node. The aux module is on USB, and the
only GPIO peripheral in the whole design is DRONE_S's optional flight
controller UART on GPIO14/15, which is untouched.

```text
Buzzer  +      -> GPIO17   (pin 11)
Buzzer  -      -> GND      (pin 9)

Green LED  +   -> GPIO27   (pin 13) through a 220-330 ohm resistor
Green LED  -   -> GND      (pin 14)

Amber LED  +   -> GPIO22   (pin 15) through a 220-330 ohm resistor
Amber LED  -   -> GND      (pin 20)

Button (optional, safe shutdown)
        one leg -> GPIO3   (pin 5)
        other   -> GND     (pin 6)
```

The LED long leg is the positive one. The resistor can sit on either side
of the LED; it limits current either way.

### The power switch

Wire the switch **in series with the positive supply lead** feeding the Pi,
before the Pi's power input. It carries the full node current, which is why
the 5 A rating matters: the Pi plus the AR9271 adapter plus the aux module
is comfortably over what a small signal switch will survive.

## Read this before fitting a bare power switch

Cutting power to a running Pi is an unclean shutdown. Do it repeatedly and
the SD card **will** eventually corrupt. That is not a theoretical worry
for this project: these nodes already lose power in the field, and one has
already been taken down by a USB brownout (CHANGES.md item 40).

Two ways to live with it, in order of preference:

1. **Fit the optional button on GPIO3.** Press it to shut down cleanly,
   wait for the green light to go out, then use the switch. GPIO3 is
   special: the same button also WAKES a halted Pi, so one button does
   both. Enable it by adding this line to `/boot/firmware/config.txt`:

   ```text
   dtoverlay=gpio-shutdown,gpio_pin=3,active_low=1,gpio_pull=up
   ```

2. **Accept the risk** and keep a spare flashed SD card. Reasonable for a
   demo, poor for a deployment.

## What the lights mean

| Light | State | Meaning |
|-------|-------|---------|
| Green | blinking | Booting. Services have not answered yet |
| Green | solid | Node is ready. Safe to walk away |
| Green | off after a long boot | Services failed to start. One long beep accompanies this |
| Amber | solid | This node can currently see at least one peer |
| Amber | off | No peers visible right now |

**The amber light is the useful one.** A dead USB Wi-Fi adapter, the exact
failure that stopped two nodes syncing during testing, shows up here
immediately as an unlit amber lamp, instead of being found by reading sync
logs an hour later.

Beeps: two short ones when the node first becomes ready, once, so you know
from across a field without looking. One long beep if it gives up waiting.
Nothing after that, on purpose, because anything that beeps repeatedly gets
muted or unplugged.

## Enabling it

Every node conf now ships with the switch already present and set to false,
so this is a one-word change in `deploy/nodes/drone_x.conf`:

```text
INDICATOR=true
```

Then on the Pi:

```bash
cd ~/rescue-mesh/deploy && sudo ./setup_node.sh a     # or b, or s
sudo systemctl status rescue-mesh-indicator
```

`setup_node.sh` installs `python3-gpiozero` itself when INDICATOR is true,
so there is no separate apt step to forget. It installs it only on nodes
that ask for it: a node with no panel fitted has no use for the library.

To test without rebooting:

```bash
sudo systemctl restart rescue-mesh-indicator
# expect two short beeps and a solid green within a few seconds
```

## If nothing happens

| Symptom | Cause |
|---------|-------|
| No sound at all, lights fine | Passive buzzer fitted where an active one is needed. A passive one needs a PWM tone and will never sound with this code |
| Service dies immediately | `python3-gpiozero` not installed, or the pins are in use. Check `journalctl -u rescue-mesh-indicator -n 20` |
| LED never lights | Backwards. The long leg goes to the GPIO side through the resistor |
| Green blinks forever | The API genuinely is not answering. That is the light doing its job: check `systemctl status rescue-mesh-api` |
| Amber never lights | Either genuinely no peers, or the USB Wi-Fi adapter has dropped off. Check `iw dev wlan1 info` before suspecting the lamp |
