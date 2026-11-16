# Changelog

## 0.6.1 (testing release)

Security hardening, from a full audit of the repository. No gameplay changes.

### iPhone connection (Connect iPhone…)
- The access key is now checked before any upload data is accepted, so an unauthorized device can't make the Apple TV buffer a large file.
- Limits: request headers up to 16 KB, files up to 256 MB, at most 8 connections at once, and idle connections close after 30 seconds. Phone-controller connections must authenticate within 10 seconds.
- Restoring a `.zip` is checked first: at most 1000 files, 256 MB per file and 512 MB in total.
- Download file names are cleaned before they go into a response header.

### Build and downloads
- The Freedoom download is checked against a pinned SHA-256 checksum before it is unpacked.
- `build-tvos.sh` checks the MoltenVK download against a pinned SHA-256, and checks that UZDoom, SDL, libvpx and OpenAL are at the exact pinned commits, so a moved upstream tag stops the build.

### Repository
- Removed an Xcode compiler cache and generated game data from the whole git history (they contained local file paths). GitHub secret scanning and push protection are now on.

## 0.6.0 (testing release)

Moves the engine from UZDoom 4.14.3 to **UZDoom 5.0.3**.

### Engine
- UZDoom 5.0.3 running on tvOS 17+. The tvOS patch was ported by hand: Discord rich presence and the Mach-O autosegment lookup no longer exist upstream, and ZMusic now comes bundled with the engine.
- Controller support was ported to UZDoom 5.0's new joystick layer. Sticks use its response curve and a radial dead zone, so the feel is a little different from 0.5.0.
- Fixed a black screen on 5.0.3: the Apple TV's GPU faulted on Metal argument buffers, so the app now turns them off for MoltenVK.
- Includes the upstream fix for uninitialized Vulkan pipeline images ([UZDoom#1116](https://github.com/UZDoom/UZDoom/issues/1116)).

### Build and tools
- `UZ_EXTERNAL_ZMUSIC=1 ./tvos/install.sh` builds ZMusic on its own as a fallback if music doesn't load.
- Developer overrides: `Caches/engine.env` (environment variables) and `Caches/engine.args` (engine arguments) are read at launch.

### Testing status
- Checked on an Apple TV 4K (2nd generation) with Freedoom. Music, gyro and touchpad aim, the iPhone controller and the new stick feel have not been re-tested on 5.0.3.

## 0.5.0 (testing release)

First public testing release of UZDoom 4.14.3 for Apple TV.

### Game
- UZDoom 4.14.3 running on tvOS 17+, with Vulkan graphics through MoltenVK and Metal.
- New installs start with settings that hold 60 fps on an Apple TV 4K (2nd generation): the software renderer at 1920×1080 with smooth scaling, vsync off and always run on.
- Pauses properly when you press the TV button. Settings and the shader cache are saved when the app goes to the background.
- Workaround for the pink title screen and menus on Apple GPUs ([UZDoom#1116](https://github.com/UZDoom/UZDoom/issues/1116)).

### Controls
- Xbox, PlayStation, Switch Pro and MFi controllers, using UZDoom's standard gamepad layout.
- Gyro aim (DualShock 4, DualSense, Switch Pro), with sensitivity and invert options.
- Touchpad aim; clicking the touchpad opens the automap (DualShock 4, DualSense).
- iPhone touchscreen controller in Safari, secured by a one-time key from a QR code.
- Controller Settings menu with a live controller test and a reset button.

### Games and saves
- Freedoom downloads on request. Your own WADs and mods can be sent from an iPhone over Wi-Fi.
- Save backup and restore from the iPhone page, including restoring a whole backup `.zip`.
- Optional iCloud sync into your own iCloud account (off by default; paid developer accounts).

### Install
- `tvos/install.sh` builds, signs with your Apple ID and installs on a paired Apple TV in one command.
- Personal signing settings live in `app/Config/Local.xcconfig`, which isn't in git.

### Known issues
- The hardware renderer breaks textures (smeared walls, flat floors). Stay on the software renderer; fixing it is planned for a future release.
- The frame rate drops above 1080p on the Apple TV 4K (2nd generation).
- Only the Apple TV 4K (2nd generation) has been tested. Reports from other models are welcome.
