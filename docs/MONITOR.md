# QuarryOS live monitor

QuarryOS sends live status by Ender Modem to a base computer. The base computer
draws the selected area, current column and depth, fuel, mined blocks and the
current task on an Advanced Monitor.

## Wiring

1. Place a base computer with an Advanced Monitor attached directly to it.
2. Attach an Ender Modem to that base computer.
3. Keep an Ender Modem attached to the Advanced Turtle; it is also used for
   GPS and the live status messages.
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

For a multi-block monitor, place all monitor blocks as one continuous
rectangle with the same facing and orientation. Otherwise CC:Tweaked treats
the pieces as separate monitors.

## If the screen stays on "Waiting for Turtle signal"

Update and reboot **both** the Turtle and the monitor computer. The Turtle
must have an Ender Modem or Wireless Modem mounted as its second Turtle upgrade
(the other side can hold the pickaxe). The monitor computer needs its own
wireless or Ender Modem attached directly to it.

Normal Wireless Modems only work over a limited distance. Use Ender Modems for
quarries far away from the base, at high depth, or in another dimension.
