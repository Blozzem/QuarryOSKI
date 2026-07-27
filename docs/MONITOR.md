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
