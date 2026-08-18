# jiggle

A mouse jiggler for macOS. Moves the cursor on a randomized schedule so the
system never reports you as idle.

Two independent ways to run it, sharing nothing but the idea:

- **`Jiggle.app`** — a menu bar app in Swift, posting `CGEvent` directly. The
  only dependency is Xcode Command Line Tools.
- **`jiggle.sh`** — a shell script driving [`cliclick`](https://github.com/BlueM/cliclick).
  Nothing to build.

Neither arrives quarantined: the app compiles on your machine, the script is
just a script. For people who will not touch the code there is also a prebuilt,
signed `.app` in a dmg (see Install) — one Gatekeeper step on first launch,
nothing after.

## Why another one

The established macOS jigglers — [Jiggler](https://github.com/bhaller/Jiggler),
Amphetamine and the dozen or so menu-bar clones — are prebuilt applications. On
recent macOS the older ones tend to fail before they do anything useful: the
bundle is unsigned or its signature predates current requirements, so the GUI
never comes up. Some alternatives are paid.

## What it actually does

Every 30–90 seconds (randomized) it moves the cursor a random distance,
smoothly, then returns it to the exact pixel it started from. That resets
`HIDIdleTime` — the same counter the OS and idle-aware software read.

Verified rather than assumed:

```
idle before jiggle:  8749 ms
idle after  jiggle:   101 ms
```

Two things it deliberately does differently from most jigglers:

- **Randomized intervals.** A fixed heartbeat every 60 seconds is itself a
  machine-shaped pattern.
- **Smooth movement with exact return.** It glides instead of teleporting one
  pixel, and puts the cursor back where it was, so there is no drift over a long
  session.

It also stays out of your way: if the cursor is not where it was left, or a key
was pressed in the last minute, someone is using the Mac and that cycle is
skipped.

## Install

Three ways in. All of them end with a signed `Jiggle.app` whose Accessibility
grant survives updates (the Signing section below explains why that needs
saying at all).

| Path | Needs | Pick it when |
|---|---|---|
| **dmg** from [Releases](https://github.com/gorokhovdenis/jiggle/releases) | one quarantine click | you just want the app |
| **installer** from [Releases](https://github.com/gorokhovdenis/jiggle/releases) | Xcode Command Line Tools | you also want `jiggle.sh`, or prefer building from source |
| **clone** | Xcode Command Line Tools | you plan to change the code |

### Download the dmg

The friendliest way if you are not going to change the code. Grab
`Jiggle-<version>.dmg` from [Releases](https://github.com/gorokhovdenis/jiggle/releases),
open it, drag Jiggle into Applications.

Because the dmg is not notarized (that costs $99/year), the first launch is
blocked by Gatekeeper. Once: right-click Jiggle in Applications and choose
**Open**, or run

```sh
xattr -dr com.apple.quarantine /Applications/Jiggle.app
```

After that it launches normally and, since it is signed with a stable
certificate, the Accessibility grant survives updates. No Xcode needed.

Build the dmg yourself from a checkout with `./make-dmg.sh` (after
`make-cert.sh` and `build-app.sh`).

### One file that builds itself

Grab `jiggle-installer.sh` from
[Releases](https://github.com/gorokhovdenis/jiggle/releases) — it is not in the
repository, being generated from it — and run:

```sh
bash jiggle-installer.sh
```

It asks where to unpack, creates `jiggle/` there, mints the signing certificate
and builds `~/Applications/Jiggle.app`. The installer is a self-extracting text
file — base64 payload, safe to send through mail or messengers. Regenerate it
from a checkout with `./make-installer.sh`. Non-interactive variants:

```sh
JIGGLE_BASE=~/code bash jiggle-installer.sh    # creates ~/code/jiggle
JIGGLE_DEST=~/tools/jig bash jiggle-installer.sh
```

### From a clone

```sh
git clone https://github.com/gorokhovdenis/jiggle.git
cd jiggle
./make-cert.sh     # once per machine, see below
./build-app.sh
open ~/Applications/Jiggle.app
```

## Accessibility permission

The cursor will not move without it, and this is the part that bites.

macOS decides which app a permission belongs to by the app's **designated
requirement**. With an ad-hoc signature — `codesign -s -`, what you get when
there is no certificate — that requirement is:

```
designated => cdhash H"fe68ba64..."
```

A hash of the binary itself. Rebuild the app and the hash changes, so the grant
stops applying — **silently**. The checkbox in System Settings stays on, the app
keeps counting moves, the cursor stands still. Nothing logs an error, because
`CGEvent.post` simply does nothing when unauthorized. Homebrew ships a dedicated
caveat about exactly this for unsigned formulae that need Accessibility, `yabai`
and `skhd` among them.

`make-cert.sh` creates a local self-signed certificate, which changes the
requirement to:

```
designated => identifier "com.gorokhovdenis.jiggle"
              and certificate root = H"ae47fa81..."
```

Tied to the identifier and the certificate rather than to the bytes of the
binary, so the grant survives any number of rebuilds. Run it once per machine.
It needs no admin rights and deliberately sets no trust settings: `codesign`
signs happily with an untrusted certificate, and TCC reads the designated
requirement, not the trust chain. The first `codesign` afterwards asks once for
access to the new private key — allow it and you will not be asked again.

Grant the permission from the app's **own** dialog on first launch. Adding
Jiggle by hand with "+" in System Settings looks equivalent and is not: such an
entry is dropped when the app restarts.

If a grant does break, reset it and relaunch:

```sh
tccutil reset Accessibility com.gorokhovdenis.jiggle
open ~/Applications/Jiggle.app
```

## Signing: Gatekeeper vs TCC

Two things about signing are easy to conflate, and the difference is the whole
story here.

**Gatekeeper** validates the trust chain at launch. A self-signed certificate is
trusted only on the machine that made it, so on any Mac but the build machine
the downloaded app is rejected exactly as an ad-hoc one would be — hence the
one-time quarantine step for the dmg. Notarization is the only way to remove it.

**TCC** — the Accessibility grant — does *not* check trust. It stores the app's
designated requirement and re-checks the binary against it. For a
certificate-signed app that requirement is `identifier + certificate root`, so
every update signed with the **same** certificate keeps the grant, even though
that certificate is untrusted on this machine. An ad-hoc app pins the requirement
to the binary's `cdhash`, so every update loses the grant.

That is why the dmg ships an app signed with one stable certificate rather than
ad-hoc: the first launch costs a quarantine click regardless, but updates then
keep the permission. Releases must therefore all be built on the same machine —
the one holding that certificate's private key.

The installer takes the other route: it builds on the target machine, where a
locally built bundle never gets quarantined at all and `make-cert.sh` mints that
machine's own certificate. No download step, no Gatekeeper, at the price of
needing Xcode Command Line Tools.

Developer ID plus notarization is the only path with neither a build step nor a
quarantine click. That is what Hammerspoon, AltTab, Rectangle, Ice and
MonitorControl all do.

## Menu bar app

The icon lives in the menu bar; no Dock icon, no window.

- click the icon → **Start** / **Stop**
- **Interval** — 5–10 sec, 30–90 sec, 1–3 min, 3–8 min
- **Movement** — subtle 4 px, normal 150 px, wide 400 px
- **Pause while I'm using the Mac** — the skip described above
- **Accessibility settings…** and **Open log**

The icon carries the state: a plain cursor when stopped, a cursor with motion
lines when running, a warning triangle when events are going nowhere. Every move
is confirmed by reading the cursor position afterwards, so "running" cannot
quietly mean "nothing is happening" — the reason that failure mode is worth
guarding against is that it looks exactly like success.

Log: `~/Library/Logs/jiggle.log`.

Autostart: System Settings → General → Login Items → add Jiggle.

### If the icon is nowhere to be seen

Most likely a menu bar manager — Hidden Bar, Ice, Bartender — has put it in its
collapsed section, which works by moving icons off-screen. Expand it and
⌘-drag the Jiggle icon to the always-visible side of the separator.

If the menu bar genuinely has no room, Jiggle falls back to a Dock icon:
clicking starts and stops it, right-clicking opens the same menu.

## Command-line version

```sh
brew install cliclick
./jiggle.sh
```

Configured entirely through the environment:

| Variable | Default | Meaning |
|---|---|---|
| `JIGGLE_MIN` | 30 | minimum pause between jiggles, seconds |
| `JIGGLE_MAX` | 90 | maximum pause, seconds |
| `JIGGLE_DELTA` | 150 | maximum cursor displacement, pixels |
| `JIGGLE_EASE` | 300 | glide smoothness; 0 is an instant jump, higher is slower and more human |
| `JIGGLE_SMART` | 1 | skip a cycle if the mouse was moved by hand |

```sh
JIGGLE_MIN=5 JIGGLE_MAX=10 JIGGLE_DELTA=400 ./jiggle.sh   # frequent and sweeping
JIGGLE_DELTA=4 JIGGLE_EASE=0 ./jiggle.sh                  # barely perceptible
```

It checks on startup that the cursor actually moves and says so instead of
pretending to work. Note that the permission belongs to the terminal running
the script, not to the script.

## Limitations

Worth being straight about:

- **This only affects the idle timer.** Software that tracks the foreground
  window, takes screenshots or logs keystrokes is unaffected by a moving cursor.
  If that is what you are up against, this tool will not help you.
- **Permissions do not transfer between machines.** They are per-machine TCC
  state, granted once per Mac, by hand.
- **`cliclick` is not bundled.** Homebrew installs the right build on the target
  machine.

## Files

| File | Purpose |
|---|---|
| `app/main.swift` | menu bar app: icon, menu, permissions |
| `app/Jiggler.swift` | the core: schedule, glide, move verification |
| `app/Log.swift` | `~/Library/Logs/jiggle.log` |
| `jiggle.sh` | the shell version, standalone |
| `make-cert.sh` | local signing certificate, once per machine |
| `build-app.sh` | builds `~/Applications/Jiggle.app`, icon and signature included |
| `make-installer.sh` | packs everything into a single self-extracting installer |
| `make-dmg.sh` | packs the built app into a dmg for GitHub Releases |
| `jiggle-icon.png` | app icon source |

## Uninstall

```sh
rm -rf ~/Applications/Jiggle.app
rm -f  ~/Library/Logs/jiggle.log
defaults delete com.gorokhovdenis.jiggle
tccutil reset Accessibility com.gorokhovdenis.jiggle
```

The signing certificate, if you made one, is in Keychain Access under
*Jiggle Local Signing*.

## License

MIT
