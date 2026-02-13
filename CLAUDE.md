# SM64 Plus - Development Context

## Project overview

SM64 Plus is a PC port of Super Mario 64 with enhancements. It builds from decompiled source code combined with assets extracted from the original N64 ROM.

## Build system

- `make` with many options. Key flags:
  - `TARGET_N64=0` (default) for PC builds
  - `CUSTOM_TEXTURES=1` (default) — textures loaded from `gfx/` at runtime, binary only stores path strings
  - `NOEXTRACT=1` — skip ROM asset extraction (assumes assets already exist)
  - `VERSION=us` (default) — ROM region
- `extract_assets.py <version>` extracts assets from `baserom.<version>.z64` using offsets in `assets.json`
- ROM path overridable via `SM64PLUS_BASEROM_<lang>` env vars

## Asset pipeline

### Textures (with CUSTOM_TEXTURES=1)
- `extract_assets.py` → PNGs in source tree → Makefile stores **filename strings** (not pixel data) in `.inc.c` → compiled into binary
- At runtime: `gfx_pc.c` loads actual PNGs from `gfx/` directory (path passed as argv[1] or relative to executable)
- The binary contains NO copyrighted texture data — only path strings

### Audio
- `extract_assets.py` → AIFF samples → `aiff_extract_codebook` + `vadpcm_enc` → AIFC → `assemble_sound.py` → binary blobs
- Four compiled-in arrays in `sound/sound_data.c`: `gSoundDataADSR`, `gSoundDataRaw`, `gMusicData`, `gBankSetsData`
- On PC: `osPiStartDma` = `memcpy` (`src/pc/ultra_reimplementation.c:20`), no `sizeof` used on arrays
- No runtime audio file loading currently exists

### Animations
- Version-controlled `.inc.c` files in `assets/anims/` — NOT from ROM

### Demo data
- Small controller input recordings extracted from ROM (`assets/demos/*.bin`)

## Flatpak

- Manifest: `flatpak/com.github.MorsGames.sm64plus.yml`
- Wrapper: `flatpak/sm64plus-wrapper.sh`
- Runtime: `org.freedesktop.Platform` 24.08
- Dependencies built as modules: libusb, capstone
- Current branch: `add-flatpak`

## Key code paths

- `src/pc/pc_main.c` — PC entry point, `GFX_DIR_PATH` global, working directory setup
- `src/pc/gfx/gfx_pc.c:829-898` — texture loading, CUSTOM_TEXTURES runtime PNG loading
- `src/pc/ultra_reimplementation.c` — N64 API reimplementation (DMA = memcpy)
- `src/audio/load.c` — audio init and bank/sequence loading
- `sound/sound_data.c` — audio data arrays

## Planned work

See `docs/external-data-plan.md` for the plan to enable ROM-free builds and first-run asset extraction in the flatpak (`EXTERNAL_DATA` build flag).
