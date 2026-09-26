# UZDoom for Apple TV

Play classic Doom on your Apple TV with a game controller.

This is a port of [UZDoom](https://github.com/UZDoom/UZDoom), a modern Doom engine, to tvOS. It comes with a simple launcher: pick a game, press play, and you're in.

> **Status: early testing.** The game runs on a real Apple TV, and graphics, sound and gameplay work. Some rough edges remain; see [Known issues](#known-issues). There is no one-tap install yet. For now you build it yourself on a Mac (steps below). A TestFlight link is planned.

---

## What you need

| To play | To build it yourself |
|---|---|
| An Apple TV 4K with tvOS 17 or later (tested on Apple TV 4K, 2nd generation) | A Mac with **Xcode** installed (free from the Mac App Store) |
| A **game controller**: Xbox, PlayStation or any "MFi" controller | **CMake** (`brew install cmake`) |
| A Doom game file (Freedoom is free and downloads automatically) | An Apple ID (free works; a paid developer account is needed for iCloud) |

### Why a controller is required

The Siri Remote has only a few buttons, which isn't enough for Doom (move, turn, fire, open doors, switch weapons…). The launcher won't start a game until a controller is connected.

To pair one, open **Settings → Remotes and Devices → Bluetooth** on the Apple TV and put your controller in pairing mode.

---

## Features

- **Freedoom included**: Freedoom is a free, legal Doom-compatible game. If you have no game files, the app downloads it for you.
- **Use your own Doom games**: add `DOOM.WAD`, `DOOM2.WAD`, `TNT.WAD`, `PLUTONIA.WAD` or mods (`.pk3`) that you own.
- **Send files from your iPhone**: no cables needed; see [Adding your own games](#adding-your-own-games).
- **Pauses properly** when you press the TV button to go back to the Home screen.
- **iCloud sync** of games and saves between your devices. This needs a paid Apple developer account and is currently switched off in test builds.

---

## Controls

Xbox, PlayStation and other MFi controllers all use the same layout:

| Control | Action |
|---|---|
| Left stick | Move and strafe |
| Right stick | Turn and look up/down |
| Right trigger (RT / R2) | Fire |
| Left trigger (LT / L2) | Alternate fire (some mods) |
| A (✕ on PlayStation) | Use / open doors |
| Y (△) | Jump |
| Left / right bumper (LB/RB, L1/R1) | Previous / next weapon |
| D-pad up | Automap |
| D-pad down / left / right | Use / previous / next inventory item |
| Left stick click | Crouch |
| Menu (≡) | Game menu |
| View / Options | Pause |

B and X (○ and □) are free for you to assign.

- **See and test it:** in the launcher, choose **Controls & Controller Test**. The layout lights up as you press each button or move a stick. Press B or Menu twice to leave.
- **Change a button:** start a game and open **Options → Customize Controls**.
- **Start over:** choose **Reset Controls to Default** in the launcher.

---

## Adding your own games

1. In the launcher, choose **Beam from iPhone…**.
2. The TV shows an address like `http://192.168.1.40:8080`.
3. On your iPhone, on the **same Wi-Fi**, open that address in Safari.
4. Pick your files:
   - `.wad`, `.pk3`, `.ipk3` go into your game library.
   - `.zds` files go into your saves.
5. Choose **Stop Receiving** when you're done. Your games now appear in the list.

> **Please only use game files you own.** The commercial Doom games are not included and must never be uploaded to this repository.

---

## Building and installing (Mac)

Allow about 30–40 minutes the first time, mostly waiting.

### 1. Download the project

Open **Terminal** on your Mac and run:

```bash
git clone https://github.com/mscproductions23/uzdoomtvos.git ~/uzdoomtvos
```

### 2. Build the game engine

```bash
cd ~/uzdoomtvos && ./tvos/build-tvos.sh
```

This downloads UZDoom and the libraries it needs, applies the Apple TV changes and builds everything. When it finishes, you'll see a summary. Running it again later is much faster, because finished parts are skipped.

### 3. Open the app in Xcode

1. Open `app/UZDoomTV.xcodeproj`.
2. Click **UZDoomTV** in the left sidebar, then open the **Signing & Capabilities** tab.
3. Under **Team**, pick your Apple ID. (Add it in Xcode → Settings → Accounts if it isn't listed.)
4. If Xcode complains about the bundle ID, change it to something unique, e.g. `com.yourname.uzdoomtv`.

### 4. Connect your Apple TV (first time only)

1. Make sure the Mac and Apple TV are on the same network.
2. On the Apple TV, open **Settings → Remotes and Devices → Remote App and Devices**.
3. In Xcode, open **Window → Devices and Simulators**. Your Apple TV should appear; click **Pair** and enter the code shown on the TV.

### 5. Run it

Choose your Apple TV at the top of the Xcode window and press **Run** (▶ or ⌘R).

The very first run can sit at **"Fetching debug symbols"** for 10–30 minutes. That's normal and happens only once per tvOS version.

> **Free Apple ID?** The app will work for **7 days**, then you'll need to press Run in Xcode again. A paid developer account gives you a full year.

---

## Updating to the newest version

```bash
cd ~/uzdoomtvos && git pull && ./tvos/build-tvos.sh
```

Then press **Run** in Xcode again.

---

## Troubleshooting

| Problem | What to do |
|---|---|
| The game list is greyed out | Connect a game controller (see [Why a controller is required](#why-a-controller-is-required)). |
| Controls feel wrong or inverted | Choose **Reset Controls to Default** in the launcher, then start the game again. |
| "Personal development teams … do not support the iCloud capability" | You're using a free Apple ID. The current test build already has iCloud switched off; run `git pull` to get it. |
| "No XCFramework found … MoltenVK.xcframework" | The engine build hasn't finished. Run `./tvos/build-tvos.sh` from inside the `uzdoomtvos` folder. |
| The build script stops with an error | It prints the name of a log file. Open it, or send the last lines with a bug report. |
| Frame drops or stutter | Running from Xcode slows the game down (debugger attached). For real performance, stop it in Xcode and open UZDoom from the Apple TV Home screen. Some stutter the first time new effects appear is shaders compiling; this gets better on later runs. |
| "Fetching debug symbols" takes forever | Wait up to 30 minutes. If it's still stuck, quit Xcode, restart the Apple TV and try again. |

For more build options (rebuilding single parts, custom settings), see [`tvos/README.md`](tvos/README.md).

---

## Known issues

- The UZDoom loading screen and the title screen could look **pink** (a known UZDoom bug on Apple GPUs, [UZDoom#1116](https://github.com/UZDoom/UZDoom/issues/1116)). This build includes a workaround that is still being tested.
- No TestFlight or one-tap install yet; building on a Mac is currently the only way.
- iCloud sync is switched off in test builds until the paid developer team is set up.

---

## How it works (for the curious)

- `app/`: the Apple TV launcher, written in SwiftUI. It finds your games, handles iPhone uploads and starts the engine.
- `tvos/build-tvos.sh`: one script that downloads UZDoom 4.14.3 and its libraries (SDL2, ZMusic, OpenAL, libvpx, MoltenVK), applies the patches and builds `UZDoomEngine.framework`.
- `tvos/patches/`: the small changes needed to make each library work on Apple TV.
- Graphics go through **Vulkan → MoltenVK → Metal**, Apple's graphics system.

More technical background is in [`NOTES.md`](NOTES.md).

---

## Credits and license

- **UZDoom** and the GZDoom/ZDoom teams: the engine. Licensed under the GNU GPL v3.
- **Freedoom**: free game content, BSD licence.
- **SDL**, **ZMusic**, **OpenAL Soft**, **libvpx**, **MoltenVK**: libraries used by the engine, each under its own licence.

This Apple TV port is not affiliated with id Software, Bethesda or the UZDoom team. *Doom* is a trademark of id Software.
