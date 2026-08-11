# Roblox Replay for macOS

This native macOS utility activates Roblox, records a mouse-and-keyboard movement,
and replays it with the original timing for a configured number of repetitions.
The recording stays in memory and is discarded when the utility exits.

## Why Swift instead of AppleScript?

AppleScript can activate Roblox and ask System Events to issue individual clicks or
keystrokes. It cannot observe an arbitrary mouse-and-keyboard sequence while you
perform it. This tool uses Apple's Core Graphics event-tap API for recording and
posting events, and AppKit to activate Roblox.

## Run it

You need macOS 13 or later and Apple's Swift toolchain. The copy of Swift included
with Xcode or the Command Line Tools works.

From Terminal:

```sh
cd roblox-auto-clicker
./run.command --count 5
```

Or double-click `run.command` in Finder and enter the repeat count when prompted.
The launcher compiles the small native executable on its first run and rebuilds it
when the source changes.

On the first run, macOS asks for Accessibility access. Enable the item macOS shows
for the request (normally Terminal or `roblox-replay`) under:

**System Settings > Privacy & Security > Accessibility**

Then quit that application and run the utility again. Depending on your macOS
privacy settings, macOS may also request **Input Monitoring** access.

## Controls

1. Start or join the Roblox experience and leave Roblox running.
2. Run the utility and configure the repeat count.
3. Roblox is brought to the front. After the countdown, perform the movement once.
4. Press **Escape** to stop recording. The utility consumes this key, so it does
   not open Roblox's menu.
5. After a two-second pause, the recording is replayed.
6. Press **Escape** during replay for an emergency stop.

Options:

```text
-n, --count NUMBER   Repetitions (1–10000)
    --countdown SEC  Recording countdown, 0–30 seconds (default: 3)
    --pause SEC      Delay between repetitions, 0–60 seconds (default: 0.5)
```

## Limitations and fair-play note

- Replays use screen coordinates, so do not move or resize the Roblox window after
  recording.
- Full-screen mode, camera-lock behavior, or an experience's input handling can make
  mouse replay less exact than ordinary desktop clicks.
- This does not modify or inject code into Roblox. Even so, automation can be against
  an experience's rules or treated as cheating. Use it only where the experience
  owner permits automation; account enforcement is your responsibility.
