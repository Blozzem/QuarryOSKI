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

## Development layout

```
install.lua             One-line remote installer
src/startup.lua         Boot entry point copied to the computer root
src/quarryos/kernel.lua Interactive QuarryOS shell
src/quarryos/lib/ui.lua Terminal rendering helpers
```

## License

MIT. CC:Tweaked is its own project and is not bundled with QuarryOS.
