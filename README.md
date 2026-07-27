# QuarryOS

QuarryOS is a small, keyboard-first operating environment for
[CC:Tweaked](https://tweaked.cc/) computers and turtles. It is designed to run
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
- An internet-enabled ComputerCraft computer (`http` must be enabled by the
  server or single-player configuration) for the one-line installer

## Install

On a CC:Tweaked computer, run:

```lua
wget run https://raw.githubusercontent.com/Blozzem/QuarryOSKI/main/install.lua
```

The installer downloads QuarryOS to `/quarryos` and creates `/startup`. If a
startup program already exists, it is copied to `/startup.quarryos-backup`.

After installation, reboot the computer or execute `startup`.

## Turtle quarry

Place one service chest containing fuel (for example coal) directly above the
turtle's starting position, then run:

```lua
/quarryos/quarry.lua
```

It digs a one-block vertical shaft until it reaches an unbreakable block
(normally bedrock). When its inventory is full or its fuel reserve is too low,
it returns to the surface, puts every collected item into the chest, takes fuel
from the same chest, refuels
and travels back to its previous depth before continuing. It returns to the
starting height when complete. Use `/quarryos/quarry.lua <depth>` to set a
maximum depth.

If Minecraft or the server restarts, run `/quarryos/quarry.lua` again on the
same turtle. QuarryOS restores its saved depth and continues the current shaft.

## In-game updates

Run `update` from the QuarryOS shell to download the current version in place.
No computer files need to be deleted; only QuarryOS files are replaced.

## Development layout

```
install.lua  One-line remote installer
startup.lua  Boot entry point copied to the computer root
kernel.lua   Interactive QuarryOS shell
ui.lua       Terminal rendering helpers
```

## License

MIT. CC:Tweaked is its own project and is not bundled with QuarryOS.
