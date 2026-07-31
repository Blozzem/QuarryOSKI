# QuarryOS optional GPS network

QuarryOS uses GPS to make sure a turtle has not been moved before it resumes a
saved quarry. GPS is **not** required to start a new quarry. A quarry started
without GPS must not be moved. When it stops at its service station, QuarryOS
checks the service chests and asks for manual confirmation before continuing.
If it stopped elsewhere, QuarryOS keeps its state safely but will not resume it
without a position check.

## Materials

- 4 CC:Tweaked computers
- 4 Wireless Modems in range, or Ender Modems for long distance
- A wireless or Ender Modem attached to the Advanced Turtle

## Setup

1. Place the four host computers around the quarry area at different X, Y and
   Z positions. Do not place all of them on a flat plane.
2. Attach one Ender Modem to each host computer.
3. Use the F3 screen to read the coordinates of each **computer block**.
4. On each host, run:

   ```lua
   gps host X Y Z
   ```

5. Make the hosts start automatically by creating `/startup.lua`:

   ```lua
   shell.run("gps", "host", X, Y, Z)
   ```

6. On the turtle, run `gps locate`. It must print three coordinates before a
   saved GPS-enabled QuarryOS quarry can resume.

The GPS hosts only need to be powered on while QuarryOS checks or resumes a
GPS-enabled quarry. A no-GPS quarry can mine normally; after it stops, it can
only be continued from the service station with manual confirmation.
