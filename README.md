# jiggle

A mouse jiggler for macOS that keeps your Mac awake by moving the cursor on a randomized schedule.

Unlike the usual suspects, it ships as **source that builds itself on your machine**. There is no
downloaded `.app`, so there is nothing for Gatekeeper to reject and no signature to go stale.

## Why another one

The established macOS jigglers — [Jiggler](https://github.com/bhaller/Jiggler), Amphetamine and the
dozen or so menu-bar clones — are prebuilt applications. On recent macOS the older ones tend to fail
before they do anything useful: the bundle is unsigned or its signature predates current requirements,
so the GUI never comes up. Some alternatives are paid.

`jiggle` sidesteps that class of problem entirely:

- the launcher `.app` is compiled locally with `osacompile` and ad-hoc signed on the spot, so it never
  carries a quarantine attribute
- the jiggler itself is a plain shell script you can read in one sitting
- the only binary dependency is [`cliclick`](https://github.com/BlueM/cliclick), installed from Homebrew

## What it actually does

Every 30–90 seconds (randomized) it moves the cursor a random distance, smoothly, then returns it to
the exact pixel it started from. That resets the system idle timer — the same `HIDIdleTime` counter
that the OS and idle-aware software read.

Verified rather than assumed:

```
idle before jiggle:  8749 ms
idle after  jiggle:   101 ms
```

Two things it deliberately does differently from most jigglers:

- **Randomized intervals.** A fixed heartbeat every 60 seconds is itself a machine-shaped pattern.
- **Smooth movement with exact return.** It glides via `cliclick -e` instead of teleporting one pixel,
  and puts the cursor back where it was, so there is no drift over a long session.

It also stays out of your way: if the cursor is not where the script left it, someone is using the
mouse, and that cycle is skipped.

## Install

Download `jiggle-installer.sh` from Releases and run it:

```bash
bash jiggle-installer.sh
```

It asks where to unpack, installs `cliclick` via Homebrew if missing, builds `~/Applications/Jiggle.app`,
and adds it to the Dock. The installer is a single self-extracting text file — base64 payload, safe to
send through mail or messengers.

Or from a clone:

```bash
git clone https://github.com/gorokhovdenis/jiggle.git
cd jiggle
./build-jiggle-app.sh
```

### Two things you must do by hand

Neither can be automated — macOS requires a human for both:

1. **System Settings → Privacy & Security → Accessibility** → enable iTerm.
   Without this the cursor will not move; the script detects the missing permission on startup and
   tells you so instead of pretending to work.
2. On the first click of the Dock icon, approve **"Jiggle" wants to control "iTerm"**.

## Usage

Click the Dock icon: a new iTerm window opens and the jiggler starts. `Ctrl-C` or closing the window
stops it.

From a terminal directly:

```bash
./jiggle.sh
```

Everything is configured with environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `JIGGLE_MIN` | 30 | minimum pause between jiggles, seconds |
| `JIGGLE_MAX` | 90 | maximum pause, seconds |
| `JIGGLE_DELTA` | 150 | maximum cursor displacement, pixels |
| `JIGGLE_EASE` | 300 | glide smoothness; 0 is an instant jump, higher is slower and more human |
| `JIGGLE_SMART` | 1 | skip a cycle if the mouse was moved by hand |

```bash
JIGGLE_MIN=5 JIGGLE_MAX=10 JIGGLE_DELTA=400 ./jiggle.sh   # frequent and sweeping
JIGGLE_DELTA=4 JIGGLE_EASE=0 ./jiggle.sh                  # barely perceptible
```

To change what the Dock icon runs, edit the `settings` line in `jiggle-launcher.applescript` and
re-run `./build-jiggle-app.sh`. Use that script rather than calling `osacompile` yourself — it
reinstalls the icon and re-signs the bundle in the right order.

## Requirements

- macOS (developed and tested on macOS 26)
- [iTerm2](https://iterm2.com) — the launcher is hardcoded to it
- Homebrew, for `cliclick`

## Limitations

Worth being straight about:

- **iTerm only.** Terminal.app, Ghostty and friends would need a different launcher.
- **`cliclick` from Homebrew is architecture-specific.** Homebrew handles this on the target machine,
  but the binary is not bundled.
- **Accessibility and Automation permissions do not transfer between machines.** They are per-machine
  TCC state; you grant them once per Mac, by hand.
- **This only affects the idle timer.** Software that tracks the foreground window, takes screenshots
  or logs keystrokes is unaffected by a moving cursor. If that is what you are up against, this tool
  will not help you.

## Files

| File | Purpose |
|---|---|
| `jiggle.sh` | the jiggler |
| `jiggle-launcher.applescript` | what the Dock icon runs; holds the settings line |
| `build-jiggle-app.sh` | builds `~/Applications/Jiggle.app`, installs the icon, signs it |
| `make-installer.sh` | packs everything into a single self-extracting `jiggle-installer.sh` |
| `jiggle-icon.png` | app icon source |

`jiggle.sh` is copied *into* the app bundle at build time and located relative to the bundle at run
time, so the app keeps working if you move or delete the source directory.

## License

MIT
