# QuarryOS

QuarryOS is a colour-first operating environment for
[CC:Tweaked](https://tweaked.cc/) **Advanced Turtles**. It is designed to run
inside a Minecraft NeoForge world where CC:Tweaked is installed.

It is deliberately a ComputerCraft program collection—not a replacement for
CC:Tweaked or a separate machine mod. This makes it portable between normal
computers, advanced computers, turtles and pocket computers.

## Features

- A friendly, colour-aware command shell
- Built-in `help`, `about`, `clear`, `cd`, `ls`, `edit`, `run`, `reboot` and
  `shutdown` commands
- Safe delegation of all other commands to the native ComputerCraft shell
- A `status` command that reports the current computer, label and fuel level
- Non-destructive installer which backs up an existing `startup` program
- Turtle quarry program that mines a vertical shaft to bedrock, auto-refuels
  from the turtle inventory and returns to its starting height

## Requirements

- Minecraft Java Edition with NeoForge
- [CC:Tweaked](https://modrinth.com/mod/cc-tweaked) for the same Minecraft
  version and loader
- An Advanced Turtle (regular turtles are intentionally not supported)
- A CC:Tweaked GPS network; QuarryOS uses it to prevent unsafe resumes if the
  turtle was moved after a restart
- An internet-enabled ComputerCraft computer (`http` must be enabled by the
  server or single-player configuration) for the one-line installer

## Install

On a CC:Tweaked computer, run:

```lua
wget run https://raw.githubusercontent.com/Blozzem/QuarryOSKI/main/install.lua
```

The installer downloads QuarryOS to `/quarryos`, detects the device and creates
the right `/startup` program automatically: QuarryOS on a turtle, the monitor
server on a computer with a monitor, or a GPS host on a normal computer. GPS
hosts ask for their coordinates when no existing GPS network can locate them.
If a startup program already exists, it is copied to `/startup.quarryos-backup`.

After installation, reboot the computer or execute `startup`.

## Turtle quarry

Place three service chests at the turtle's starting corner: fuel on top, ores
and valuables on the left, and normal blocks on the right. A setup menu checks
for the chests and asks for freely selectable width, length and depth (`0` means
mine until bedrock):

```lua
/quarryos/quarry.lua
```

It mines every column in the selected area. After each column it returns to the
starting corner, sorts its items into the output chests, refuels and continues
with the next column. Progress survives restarts. Use `stats` to view statistics
for the last completed quarry.

If Minecraft or the server restarts, run `/quarryos/quarry.lua` again on the
same turtle. QuarryOS restores its saved depth and continues the current shaft.

## In-game updates

Run `update` from the QuarryOS shell to download the current version in place.
No computer files need to be deleted; only QuarryOS files are replaced.

## Guides

- [GPS network setup](docs/GPS.md)
- [Live monitor setup](docs/MONITOR.md)

## Development layout

```
install.lua  One-line remote installer
startup.lua  Boot entry point copied to the computer root
kernel.lua   Interactive QuarryOS shell
ui.lua       Terminal rendering helpers
```

## License

MIT. CC:Tweaked is its own project and is not bundled with QuarryOS.
