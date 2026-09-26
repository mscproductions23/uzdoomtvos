# UZDoom for Apple TV

Play classic Doom on your Apple TV with a game controller, or with your iPhone as a touchscreen controller.

This is a port of [UZDoom](https://github.com/UZDoom/UZDoom), a modern Doom engine, to tvOS. It comes with a simple launcher: pick a game, press play, and you're in.

> **Status: early testing.** The game runs at 60 fps on a real Apple TV 4K, with working graphics, sound, saves and controls. Some rough edges remain; see [Known issues](#known-issues). There is no one-tap install yet. For now you build it yourself on a Mac (steps below). A TestFlight link is planned.

---

## What you need

| To play | To build it yourself |
|---|---|
| An Apple TV 4K with tvOS 17 or later (tested on Apple TV 4K, 2nd generation) | A Mac with **Xcode** installed (free from the Mac App Store) |
| A **game controller** (Xbox, PlayStation or any "MFi" controller), or your **iPhone** as a touchscreen controller | **CMake** (`brew install cmake`) |
| A Doom game file (Freedoom is free and downloads automatically) | An Apple ID (a free one works but has no iCloud sync; a paid developer account adds it) |

### Why a controller is required

The Siri Remote has only a few buttons, which isn't enough for Doom (move, turn, fire, open doors, switch weapons…). The launcher won't start a game until a controller is connected. Your iPhone counts: see [iPhone as a controller](#iphone-as-a-controller).

To pair one, open **Settings → Remotes and Devices → Bluetooth** on the Apple TV and put your controller in pairing mode.

---

## Features

- **Freedoom included**: Freedoom is a free, legal Doom-compatible game. If you have no game files, the app downloads it for you.
- **Use your own Doom games**: add `DOOM.WAD`, `DOOM2.WAD`, `TNT.WAD`, `PLUTONIA.WAD` or mods (`.pk3`) that you own.
- **Send files from your iPhone**: no cables needed; see [Adding your own games](#adding-your-own-games). The same page backs up your saves; see [Your saves](#your-saves).
- **Pauses properly** when you press the TV button to go back to the Home screen.
- **iCloud sync** of games and saves between your devices. It's off by default; switch it on in the launcher. Everything works offline without it.
- **iPhone as a controller**: a touchscreen gamepad in Safari, no app needed.
- **Tuned for Apple TV**: new installs start with settings that hold 60 fps. Your own changes are saved automatically.

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

- **Controller Settings:** in the launcher, choose **Controller Settings…** for gyro and touchpad aiming, the layout tester and resetting controls.
- **See and test it:** in **Controller Settings…**, choose **Controls & Controller Test**. The layout lights up as you press each button or move a stick. **Hold** B or Menu to leave.
- **Change a button:** start a game and open **Options → Customize Controls**.
- **Start over:** choose **Reset Controls to Default** in **Controller Settings…**.

### Gyro, touchpad and mouse

Turn these on in **Controller Settings…**. They apply the next time you start a game.

- **Gyro aim** (DualShock 4, DualSense, Switch Pro): tilt and turn the controller to aim, on top of the right stick. You can set the sensitivity and invert each direction.
- **Touchpad aim** (DualShock 4, DualSense): swipe the touchpad to aim. Clicking the touchpad opens the automap.
- **Mouse:** a mouse works when tvOS reports it as one: move to look, click to fire. Whether a particular device, such as a Switch 2 Joy-Con in mouse mode, is reported as a mouse is up to tvOS and hasn't been tested.

### iPhone as a controller

No controller? Use your iPhone:

1. In the launcher, choose **Connect iPhone…** and scan the QR code (same Wi-Fi).
2. Tap **🎮 Use this phone as a controller**, then turn the phone sideways.
3. Left thumb moves (the stick appears wherever you touch), right thumb looks. The buttons are FIRE, USE and JUMP, plus Menu, Back, Map and weapon switching along the top.

The phone keeps its screen on while connected, reconnects by itself if the Wi-Fi drops, and the connection stays open as long as you're playing. A real controller and the phone can be used at the same time. Only one phone can be the controller at a time.

---

## Adding your own games

1. In the launcher, choose **Connect iPhone…**.
2. The TV shows a QR code. On your iPhone, on the **same Wi-Fi**, scan it with the Camera app and open the link.
3. The page opens in Safari. The link contains a one-time key, so someone on your Wi-Fi can't just open the page without scanning the code. The connection switches itself off after 15 minutes, unless the phone is being used as a controller.

   > The connection is plain HTTP, so it isn't encrypted. Use it on your home Wi-Fi, not on public or shared networks.
4. Pick your files:
   - `.wad`, `.pk3`, `.ipk3` go into your game library.
   - `.zds` files go into your saves.
   - A `.zip` (such as a saves backup) is unpacked: saves go to your saves, and games to your library.
5. Choose **Disconnect iPhone** when you're done. Your games now appear in the list.

> **Please only use game files you own.** The commercial Doom games are not included and must never be uploaded to this repository.

---

## Your saves

Saves are kept on the Apple TV. They survive updates, but **deleting the app erases them**, and tvOS may clear them if the Apple TV runs very low on storage. To back them up:

1. In the launcher, choose **Connect iPhone…** and scan the QR code with your iPhone (same Wi-Fi).
2. Under **Back up your saves**, tap a save to download it, or **Download all saves (.zip)**.
3. To restore, open the same page and send the backup `.zip` (or single `.zds` saves) with **Send to Apple TV**. No need to unzip; the Apple TV unpacks it.

### Sync with your own iCloud

Saves sync to the **iCloud account signed in on the Apple TV**, into that account's private storage. Only that account can see them; the app's developer can't.

1. On the Apple TV, open **Settings → Users and Accounts** and make sure you're signed in to iCloud. (Apps can't sign you in themselves; tvOS always uses this account.)
2. In the launcher, switch **iCloud Sync** on. The line under it confirms the account is working, or tells you what to fix.
3. Play as usual. Saves download when you start a game and upload when you leave the app.

If several people use the Apple TV, each person's saves go to their own iCloud when they're the active user. Switch **iCloud Sync** off to keep everything on the Apple TV only.

---

## Default settings

A new install starts with settings tuned on an Apple TV 4K (2nd generation) to hold 60 fps:

| Setting | Value | Why |
|---|---|---|
| Renderer | Software | Holds 60 fps and avoids the hardware renderer's texture problems |
| Resolution | 1920 × 1080, smoothly scaled | Higher resolutions drop below 60 fps on this chip |
| Vsync | Off | Turning it on makes the frame rate drop sharply |
| Always run | On | |
| Texture filter | None | The classic look. Smooth filtering breaks textures in the hardware renderer |
| Screen size / HUD | Full-screen view, modern HUD and border scaling | The "classic" border scaling draws broken stripes |

Change anything in the game's **Options** menu. Your settings are saved automatically, even if you leave with the TV button.

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
5. **iCloud:** the project uses the maintainer's iCloud container, which your team can't use. With a paid developer account, use your own: pick a container ID such as `iCloud.com.yourname.uzdoomtv` and put it in `app/UZDoomTV.entitlements` and `app/Sources/App/DoomCloudStore.swift`, then tick it under **iCloud** on the same tab. With a free Apple ID, turn iCloud off instead (see [Troubleshooting](#troubleshooting)).

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
| The game list is greyed out | Connect a game controller, or connect your iPhone as one (see [Why a controller is required](#why-a-controller-is-required)). |
| Controls feel wrong or inverted | Choose **Reset Controls to Default** in the launcher, then start the game again. |
| Xcode says your team doesn't support the iCloud capability | You're building with a free Apple ID, which can't use iCloud. In Xcode, clear **Code Signing Entitlements** and remove `UZ_ICLOUD` from **Active Compilation Conditions** to build without iCloud. Everything except iCloud sync still works. |
| The launcher says there's no iCloud account | Sign in under **Settings → Users and Accounts** on the Apple TV, then go back to the launcher. See [Sync with your own iCloud](#sync-with-your-own-icloud). |
| Xcode asks about the iCloud container, or says no container is selected | On **Signing & Capabilities → iCloud**, tick the container named in `app/UZDoomTV.entitlements`, or press **+** to create it. If you build under your own team, use your own container (see [step 3](#3-open-the-app-in-xcode)). |
| "No XCFramework found … MoltenVK.xcframework" | The engine build hasn't finished. Run `./tvos/build-tvos.sh` from inside the `uzdoomtvos` folder. |
| The build script stops with an error | It prints the name of a log file. Open it, or send the last lines with a bug report. |
| Frame drops or stutter | Running from Xcode slows the game down (debugger attached). For real performance, stop it in Xcode and open UZDoom from the Apple TV Home screen. Also keep vsync off and the resolution at 1080p (see [Default settings](#default-settings)). Some stutter the first time new effects appear is shaders compiling; this gets better on later runs. |
| The phone controller says "Reconnecting…" | Make sure the phone is on the same Wi-Fi and the TV still shows the QR code (**Connect iPhone…**). If it doesn't recover, scan the QR code again: each connection uses a new key. |
| "Fetching debug symbols" takes forever | Wait up to 30 minutes. If it's still stuck, quit Xcode, restart the Apple TV and try again. |

For more build options (rebuilding single parts, custom settings), see [`tvos/README.md`](tvos/README.md).

---

## Known issues

- **Keep vsync off.** Turning it on makes the frame rate drop sharply. The new-install defaults leave it off.
- **Smeared textures with the hardware renderer.** With the hardware (GPU) renderer and texture filtering on, distant walls smear into stripes and floors turn flat grey. New installs use the software renderer, which holds 60 fps on an Apple TV 4K and doesn't have this problem.
- **Striped status-bar border with "classic" border scaling.** The pattern beside the status bar breaks up into stripes. New installs use the non-classic scaling, which draws correctly.
- The pink title screen (a UZDoom bug on Apple GPUs, [UZDoom#1116](https://github.com/UZDoom/UZDoom/issues/1116)) is fixed by a workaround in this build.
- **Above 1080p the frame rate drops.** The software renderer draws on the CPU, and the Apple TV 4K (2nd gen, A12) holds 60 fps at 1080p but not at 1440p or 4K. A 4K TV still looks fine, because the Apple TV scales the picture up.
- **The iPhone controller has a little lag** compared with a real controller, because it goes over Wi-Fi.
- No TestFlight or one-tap install yet; building on a Mac is currently the only way.

---

## How it works (for the curious)

- `app/`: the Apple TV launcher, written in SwiftUI. It finds your games, runs the small web server for the iPhone (files, save backups and the touch controller), syncs with iCloud, and starts the engine.
- `tvos/build-tvos.sh`: one script that downloads UZDoom 4.14.3 and its libraries (SDL2, ZMusic, OpenAL, libvpx, MoltenVK), applies the patches and builds `UZDoomEngine.framework`.
- `tvos/patches/`: the small changes needed to make each library work on Apple TV.
- Graphics go through **Vulkan → MoltenVK → Metal**, Apple's graphics system.

More technical background is in [`NOTES.md`](NOTES.md).

---

## Credits and license

- **UZDoom** and the GZDoom/ZDoom teams: the engine. Licensed under the GNU GPL v3.
- **UZDoom logo** © 2025 The UZDoom Team, licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The app icon, Top Shelf images and launcher logo are adapted from it (recoloured background, resized) and are shared under the same license.
- **Freedoom**: free game content, BSD licence.
- **SDL**, **ZMusic**, **OpenAL Soft**, **libvpx**, **MoltenVK**: libraries used by the engine, each under its own licence.

This Apple TV port is not affiliated with id Software, Bethesda or the UZDoom team. *Doom* is a trademark of id Software.
