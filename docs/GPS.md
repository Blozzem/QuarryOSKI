# QuarryOS GPS network

QuarryOS uses GPS to make sure a turtle has not been moved before it resumes a
quarry. GPS is required for new quarry plans.

## Materials

- 4 CC:Tweaked computers
- 4 Ender Modems (recommended; normal wireless modems have limited range)
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
   QuarryOS quarry can start or resume.

The GPS hosts must remain powered on while the quarry is running.
