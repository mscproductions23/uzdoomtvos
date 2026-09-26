# Changelog

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
