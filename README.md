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
- Turtle quarry program that clears full horizontal layers, auto-refuels from
  its service chest and safely returns to its starting corner
- Live monitor control centre with alerts, fuel checks and support for several
  independently running Turtles
- Web dashboard with a live quarry map, 16-slot Turtle inventory, mined-block
  statistics and safe remote control through a dedicated CC:Tweaked gateway

## Requirements

- Minecraft Java Edition with NeoForge
- [CC:Tweaked](https://modrinth.com/mod/cc-tweaked) for the same Minecraft
  version and loader
- An Advanced Turtle (regular turtles are intentionally not supported)
- A CC:Tweaked GPS network is optional. It enables QuarryOS to check a saved
  turtle position and resume safely after a restart.
- An internet-enabled ComputerCraft computer (`http` must be enabled by the
  server or single-player configuration) for the one-line installer

## Install

On a CC:Tweaked computer, run:

```lua
wget run https://raw.githubusercontent.com/Blozzem/QuarryOSKI/main/install.lua
```

The installer downloads QuarryOS to `/quarryos`, detects the device and creates
the right `/startup` program automatically: QuarryOS on a turtle or the monitor
server on a computer with a monitor. On a normal computer it optionally offers
to create a GPS host. GPS hosts ask for their coordinates when no existing GPS
network can locate them.
If a startup program already exists, it is copied to `/startup.quarryos-backup`.

After installation, reboot the computer or execute `startup`.

## Turtle quarry

Place three service chests at the turtle's starting corner: fuel on top, ores
and valuables on the left, and normal blocks on the right. Point the turtle
towards the quarry and leave the block directly in front of it free; that is the
first quarry cell and the access shaft for deeper layers. A setup menu checks
for the chests and asks for freely selectable width, length and depth (`0` means
mine until bedrock):

```lua
q
```

Mined Coal (including modded Coal variants) is returned to the top fuel chest,
not the normal-block chest, so it can be used for later refuelling.

It clears every horizontal layer in a zig-zag path before descending directly
into the next one and reversing the path. It returns to the starting corner only
when the inventory is full, fuel reaches a safe return reserve, at the final
layer, or when a service pause is requested. There it sorts items into the
output chests, refuels as far as possible (up to its full fuel capacity) and
continues. It takes full fuel stacks from the top chest, returning any unused
items when its tank is full. Progress survives restarts. In bedrock
mode it finishes the complete first layer where bedrock is encountered, which
keeps the quarry floor level and safe. Use `stats` to view statistics for the
last completed quarry. It lists mined ore blocks separately and shows the ten
most common block types; use `stats all` for the complete block list. These are
mined blocks, not item drops, so the numbers remain clear with Silk Touch,
Fortune and modded drops. `history` includes a short ore summary for each new
completed quarry. The Turtle screen and live monitor show percentage and an
estimated remaining time. Custom fixed-depth plans are exact; bedrock plans use
the usual Overworld bedrock level as a clearly marked approximation.

GPS is optional for a **new** quarry. If no GPS network is found, QuarryOS uses
the Turtle's current facing direction as its local forward direction and starts
normally. Do not move a no-GPS quarry. If it stops at the service station,
QuarryOS checks the chests there and asks you to confirm that it is still at
its original service corner before it continues. If it stops anywhere else,
its saved location cannot be checked, so QuarryOS deliberately refuses to
continue it. Run `q new` at the service corner to archive that unfinished job
and begin another one. A GPS-enabled quarry keeps the automatic
restart-and-position-check behaviour.

For service trips, it rises immediately to the already-clear service level,
then crosses directly to the access shaft instead of retracing the entire
mining snake underground. If that short route is blocked by an entity,
QuarryOS falls back to the recorded safe route.

When work resumes from the service station, it uses the same safe principle in
reverse: it travels directly across the surface to the saved work cell and
only then descends.

## Emergency mode

Emergency auto-return is enabled for every new quarry. If QuarryOS cannot move,
mine or replay its saved route safely, it records the precise problem, alerts
the monitor and makes one non-digging attempt to return to the service station.
There it unloads, refuels and pauses. If that route is blocked too, the Turtle
stays exactly where it is rather than forcing its way through; clear the path
and run `q` to retry recovery. GPS failures and service-station problems are
also saved as an emergency instead of being silently treated as normal work.

The live monitor's Settings screen can turn automatic emergency return on or
off for the selected Turtle. Turning it off never makes the Turtle continue
through a problem: it still stops and records the reason, but does not try to
travel back automatically.

## Liquid Guard

When Lava is detected below, the Turtle briefly places and removes a normal
block in that Lava field, then records the position. In the following layer it
passes through the flow, checks the four surrounding walls and only seals a
Lava source block (`level = 0`) found in a wall. Flowing Lava itself is left
alone, so the actual entry point is closed instead. **Water is ignored
completely:** it is not recorded, tested, sealed or removed. QuarryOS keeps one
stack of common building blocks (Cobblestone, Stone, Deepslate, Dirt and similar
blocks) in **slot 16** (the bottom-right turtle slot) as a Lava-sealing reserve.
This is a fixed reserve slot: QuarryOS never unloads an item that you put there.
Fill it with a suitable block before starting. If that slot is empty, QuarryOS
also tries to take a stack from the right normal-block chest. If none is
available it pauses safely at the service station and tells you exactly which
slot to fill. Add a suitable block to slot 16 (or the right chest) and run `q`
to continue. When the quarry is fully complete, its final service visit empties
slot 16 into the right chest too.

Quarry plans include Small (16x16), Medium (32x32), Large (64x64) and a custom
size. Before starting, QuarryOS estimates blocks and fuel. Use `history` for
previous jobs and `selftest` to check the complete setup.

If Minecraft or the server restarts, run `q` again on the same turtle. When a
job is saved, QuarryOS first shows a menu with **Resume**, **View detailed
status**, **Archive and plan a new quarry**, and **Cancel**. Only choosing
Resume reaches the normal chest, GPS and position safety checks. GPS-enabled
quarries check their GPS position and continue at the saved layer and cell. A
quarry that was started without GPS is kept safely but cannot be resumed if it
stopped away from its service station, because its location cannot be verified.
At the service station it asks for your manual confirmation before continuing.
To skip the menu and create a new plan directly, run `q new`; the old progress
is archived instead of deleted.

## In-game updates

Run `update` from the QuarryOS shell to download the current version in place.
It shows the installed and available version, checks every QuarryOS program
file, then replaces only files whose contents changed. All changed files are
downloaded to a temporary staging area before anything is replaced, so a failed
download leaves the installed program unchanged. The standard Turtle and
Monitor startup first repairs an interrupted update before QuarryOS starts; a
custom `/startup` file is deliberately left untouched and can recover by
running `update` again. Run `update check` to see the version and changed-file
count without changing anything. No user data, quarry state, history or monitor
settings are replaced.

## Guides

- [GPS network setup](docs/GPS.md)
- [Live monitor setup](docs/MONITOR.md)
- [Web-Dashboard und Minecraft-Verbindung](docs/WEB.md)

## Development layout

```
install.lua  One-line remote installer
startup.lua  Stable recovery boot entry copied to the computer root
kernel.lua   Interactive QuarryOS shell
ui.lua       Terminal rendering helpers
VERSION      Release version shown by update check
```

## License

MIT. CC:Tweaked is its own project and is not bundled with QuarryOS.
