# QuarryOS live monitor

QuarryOS sends live status by Wireless or Ender Modem to a base computer. The
base computer draws the selected area, current column and depth, fuel, mined
blocks, current task, percentage and estimated remaining time on an Advanced
Monitor.

## Wiring

1. Place a base computer with an Advanced Monitor attached directly to it.
2. Attach a Wireless or Ender Modem to that base computer.
3. Keep a Wireless or Ender Modem attached to the Advanced Turtle for live
   status messages. GPS is optional and needs its own GPS host network only
   when safe restart-and-position checking is wanted.
4. On the base computer, run:

   ```lua
   /quarryos/monitor_server.lua
   ```

5. Start `/quarryos/quarry.lua` on the turtle. The live screen updates
   automatically.

Use a larger multi-block Advanced Monitor for the clearest display. If the
base monitor server is offline, the quarry continues normally using the turtle
display.

QuarryOS automatically selects a layout and the largest suitable text size. A
1x2 monitor is physically narrow, so it normally uses a short dashboard at
scale 0.5 instead of cutting off long lines. A correctly connected 3x3 or 5x5
monitor has more room and therefore receives a larger scale automatically. The
server also recalculates after a monitor is resized; its computer console prints
the detected layout, scale and character size for troubleshooting.

For a plan with a selected depth, the percentage and ETA are calculated from
that exact depth. A `0 = bedrock` plan has no known final depth, so QuarryOS
marks these values with `~`: they are a useful estimate based on the usual
Overworld bedrock level and the Turtle's measured mining speed.

For a multi-block monitor, place all monitor blocks as one continuous
rectangle with the same facing and orientation. Otherwise CC:Tweaked treats
the pieces as separate monitors.

## Several Turtles and monitor controls

One monitor can track several QuarryOS Turtles at once. Touch a Turtle in the
**TURTLES** list to select it; every command is sent directly to that selected
Turtle, never to all of them. Give Turtles names with CC:Tweaked's normal
`label` command to make the list easier to read.

On a compact monitor, touch the title bar to return to the Turtle list.
The selected Turtle has these buttons:

- **SVC**: return to the service station, unload, refuel and pause.
- **STOP**: finish the current layer, then return to the service station and
  pause. It never interrupts a movement or mining action halfway through.
- **FUEL**: ask the Turtle for its current fuel, safe fuel requirement and any
  shortfall. This checks the Turtle's fuel; it does not remove fuel from the
  chest.
- **title bar**: return to the Turtle list and choose another Turtle.
- **ALARMS**: show the last 20 QuarryOS notifications.
- **MAP**: show a top-down, scaled view of the selected Turtle's current
  layer. Completed cells, the current Turtle position and the unmined area are
  shown with different colours.
- **SETTINGS**: open monitor options. It can mute/unmute the local Speaker and
  enable or disable automatic emergency return for the selected, currently
  running Turtle.
- **UPDATE**: update and reboot this monitor computer only. It never updates,
  pauses or reboots a Turtle.

On a narrow 1x2 monitor, touch the title to cycle through the available buttons,
then touch the large bottom button. This keeps every control usable on a small
screen.

## Notifications

The monitor records start, service-pause, stop-after-layer and completion
messages. Warnings and completions are also played through an attached
CC:Tweaked Speaker when one is available. A Turtle which has not sent a status
message for 30 seconds is displayed as **OFF** in the Turtle list.

The Settings screen's sound switch affects this monitor computer only. It does
not silence other monitors or change the Turtle. Emergency auto-return is on by
default: an unexpected blocked route is recorded and the Turtle tries to return
without digging; if the return route is blocked too, it stops in place and
reports the reason.

## Service and pause from the monitor

Touch the red **SERVICE & PAUSE** button on the live display. It sends a
service-and-pause request directly to the Turtle which last reported that
quarry's status. The Turtle returns to the service station, unloads, refuels
and pauses at its next safe movement point.

The monitor first shows only **Request sent**. This confirms that its modem
sent the request, not that the Turtle has already received it or paused. When
the Turtle accepts it, the monitor changes this to **Request confirmed**.
Confirmation means that the command was accepted, not that the Turtle has
already reached service; wait for the next Turtle status update before assuming
it has paused there. If no confirmation appears, touch the button again to
resend the same safe request to that Turtle.

To continue the paused quarry, go to the Turtle and run:

```lua
q
```

The monitor button does not resume a quarry, so it cannot start the Turtle by
accident. Update both the Turtle and the monitor computer before using this
control.

## If the screen stays on "Waiting for Turtle signal"

Update and reboot **both** the Turtle and the monitor computer. The Turtle
must have an Ender Modem or Wireless Modem mounted as its second Turtle upgrade
(the other side can hold the pickaxe). The monitor computer needs its own
wireless or Ender Modem attached directly to it.

Normal Wireless Modems only work over a limited distance. Use Ender Modems for
quarries far away from the base, at high depth, or in another dimension.
