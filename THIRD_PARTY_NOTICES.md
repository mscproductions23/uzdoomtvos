# Third-party notices

UZDoom for Apple TV is licensed under the GNU GPL v3 (see [LICENSE](LICENSE)). It builds on
the following projects, each under its own license. Only source code and small assets are kept in
this repository. `tvos/build-tvos.sh` downloads the rest from the upstream projects when you build.

| Component | Used for | License |
|---|---|---|
| [UZDoom](https://github.com/UZDoom/UZDoom) 4.14.3 | The game engine (patched by `tvos/patches/uzdoom`) | GPL v3 or later |
| UZDoom asset packages (`uzdoom.pk3`, `game_support.pk3`, `game_widescreen_gfx.pk3`, `brightmaps.pk3`, `lights.pk3`) | Built from UZDoom's `wadsrc*` folders and bundled into the app | See UZDoom's `LICENSE` and the `license.md` files in `wadsrc_bm`, `wadsrc_extra` and `wadsrc_widepix` |
| UZDoom logo | App icon, Top Shelf images, launcher logo and README banner (`app/Sources/App/Assets.xcassets`, `docs/images/banner.png`), adapted by recolouring, resizing and adding text | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), © 2025 The UZDoom Team. The adapted images are shared under the same license |
| [SDL](https://github.com/libsdl-org/SDL) 2.32.10 | Window, input and events (patched by `tvos/patches/sdl2`) | zlib |
| [ZMusic](https://github.com/UZDoom/ZMusic) 1.1.14 (full version) | Music playback, including FluidSynth (patched by `tvos/patches/zmusic`) | GPL v3 (see its `licenses` folder for the parts it includes) |
| [OpenAL Soft](https://github.com/kcat/openal-soft) 1.24.3 | Sound | LGPL v2.1 or later |
| [libvpx](https://github.com/webmproject/libvpx) 1.15.2 | Video playback (VP8/VP9 decoding) | BSD 3-Clause |
| [MoltenVK](https://github.com/KhronosGroup/MoltenVK) 1.4.2 | Vulkan graphics on Apple's Metal | Apache 2.0 |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (`app/Vendor/ZIPFoundation`) | Unpacking Freedoom and save backups | MIT |
| [Freedoom](https://freedoom.github.io/) | Free game content, downloaded by the app on request | BSD 3-Clause |
| [Noto Sans](https://fonts.google.com/noto) | Lettering in the README banner | SIL Open Font License 1.1 |

*Doom* is a trademark of id Software. This project is not affiliated with id Software, Bethesda,
ZeniMax or the UZDoom team. Commercial game files (`DOOM.WAD`, `DOOM2.WAD`, …) are not included
and must never be added to this repository.
