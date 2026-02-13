# Plan: First-run ROM asset extraction for Flatpak

## Context

The flatpak currently builds SM64 Plus with a ROM present, then ships the binary + extracted `gfx/` textures. ROM-extracted assets cannot be legally redistributed.

### Key findings

1. **Textures are NOT in the binary** with `CUSTOM_TEXTURES=1` (the default). The Makefile at line 686 stores only path strings in `.inc.c` files — not pixel data. Real textures are loaded from the `gfx/` directory at runtime. The binary is already clean of texture data.

2. **Audio data IS compiled into the binary** (`sound/sound_data.c`) as four byte arrays: `gSoundDataADSR`, `gSoundDataRaw`, `gMusicData`, `gBankSetsData`. However, on PC, `osPiStartDma` is just `memcpy` (`src/pc/ultra_reimplementation.c:20`), and no `sizeof` is used on these arrays. They can be changed to pointers loaded from files at runtime.

3. **Animations** are version-controlled `.inc.c` files in `assets/anims/`, NOT extracted from ROM.

4. **Demo data** (controller input recordings in `assets/demos/*.bin`) is extracted from ROM but is small and arguably not copyrightable art.

## Approach: Build without ROM, extract everything at first run

### Phase 1: Enable ROM-free build

#### 1a. Add `EXTERNAL_DATA` build flag to Makefile

When `EXTERNAL_DATA=1`:
- Skip `extract_assets.py` (set `NOEXTRACT=1` implicitly)
- Generate placeholder PNG files from `assets.json` (empty 1-byte files — the CUSTOM_TEXTURES build only reads the filename, never the pixel data)
- Use stub audio arrays instead of ROM-extracted audio

**File: `Makefile`**
- Add `EXTERNAL_DATA ?= 0` option
- When `EXTERNAL_DATA=1`: auto-set `NOEXTRACT=1`, run a script to create placeholder PNGs, add `-DEXTERNAL_DATA` to `CFLAGS`

#### 1b. Create placeholder generation script

**New file: `tools/generate_placeholders.py`**
- Reads `assets.json`
- Creates empty files at every PNG path (just needs to exist as a file)
- Creates empty files at every `.aiff` and `.m64` path
- Creates empty `assets/demos/*.bin` files matching `assets/demo_data.json`
- This lets the Makefile's dependency resolution work without a ROM

#### 1c. Modify sound_data.c for external loading

**File: `sound/sound_data.c`**
```c
#ifdef EXTERNAL_DATA
// Minimal stubs — replaced at runtime by file loading
unsigned char _gSoundDataADSR_stub[] = { 0, 0 };
unsigned char _gSoundDataRaw_stub[] = { 0, 0 };
unsigned char _gMusicData_stub[] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
unsigned char _gBankSetsData_stub[] = { 0 };
unsigned char *gSoundDataADSR = _gSoundDataADSR_stub;
unsigned char *gSoundDataRaw = _gSoundDataRaw_stub;
unsigned char *gMusicData = _gMusicData_stub;
unsigned char *gBankSetsData = _gBankSetsData_stub;
#else
// Original arrays
unsigned char gSoundDataADSR[] = { #include "sound/sound_data.ctl.inc.c" };
// ... etc
#endif
```

**File: `src/audio/load.c`** (and `load_sh.c`)
- Change `extern u8 gSoundDataADSR[];` → `extern u8 *gSoundDataADSR;` (only when `EXTERNAL_DATA`)

**Note**: The `gMusicData` stub needs at least 16 bytes because `audio_init()` reads the first 0x10 bytes to get `seqCount`. A zeroed header with `seqCount=0` will cause `audio_init` to skip loading sequences gracefully, meaning the game runs silently without crashing.

#### 1d. Add audio file loading function

**File: `src/pc/pc_main.c`** (or a new `src/pc/external_data.c`)

Add a function `load_external_audio(const char *data_dir)` called before `audio_init()`:
- Looks for `sound_data.ctl`, `sound_data.tbl`, `sequences.bin`, `bank_sets` in `data_dir`
- If found: `malloc` + `fread` each file, assign to the global pointers
- If not found: leave stubs (game runs without audio)

This is called from `main_func()` before the main game loop starts.

### Phase 2: Runtime asset extraction

#### 2a. Create extraction script

**New file: `flatpak/extract-assets.sh`** (installed to `/app/bin/`)

This script:
1. Takes ROM path and output directory as arguments
2. Sets up a temp working directory with symlinks to tools in `/app/lib/sm64plus/`
3. Runs `extract_assets.py us` to extract all assets from ROM
4. Copies texture PNGs to `$OUTPUT_DIR/gfx/` (mirroring Makefile lines 598-608):
   - `textures/` directory
   - `actors/**/*.png`
   - `levels/**/*.png`
   - Skybox tiles from the build
5. Runs the sound build pipeline to produce the 4 binary sound files:
   - Build AIFC files from extracted AIFFs (using `aiff_extract_codebook` + `vadpcm_enc`)
   - Run `assemble_sound.py` to produce `sound_data.ctl`, `sound_data.tbl`, `sequences.bin`, `bank_sets`
   - Copy these to `$OUTPUT_DIR/sound/`
6. Cleans up temp dir

Required tools to ship in flatpak (pre-built during flatpak build):
- `tools/n64graphics`, `tools/skyconv`, `tools/mio0` (texture extraction)
- `tools/aiff_extract_codebook`, `tools/vadpcm_enc` (audio encoding)
- `tools/aifc_decode` (audio decoding)
- `tools/disassemble_sound.py`, `tools/assemble_sound.py` (Python scripts)
- `extract_assets.py`, `assets.json`, `sm64.us.sha1`
- `sound/sound_banks/*.json`, `sound/sequences.json`, `sound/sequences/` (sound bank/sequence definitions)
- `tools/determine-endian-bitwidth.c` (or pre-generate the endian-bitwidth output)

#### 2b. Rewrite wrapper script

**File: `flatpak/sm64plus-wrapper.sh`**

```sh
#!/bin/sh
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/sm64plus"
GFX_DIR="$DATA_DIR/gfx"
SOUND_DIR="$DATA_DIR/sound"
ROM_PATH="$DATA_DIR/baserom.us.z64"

# Check if assets already extracted
if [ -d "$GFX_DIR" ] && [ -d "$SOUND_DIR" ]; then
    export SM64PLUS_SOUND_DIR="$SOUND_DIR"
    exec /app/bin/sm64plus "$GFX_DIR" "$@"
fi

# Check for ROM
if [ ! -f "$ROM_PATH" ]; then
    zenity --error --title="SM64 Plus" \
        --text="Place your baserom.us.z64 in:\n$DATA_DIR/\n\nThen launch again."
    exit 1
fi

# Extract assets
zenity --info --title="SM64 Plus" \
    --text="First-run setup: extracting assets from ROM.\nThis may take a moment."

/app/bin/extract-assets.sh "$ROM_PATH" "$DATA_DIR"

if [ $? -ne 0 ]; then
    zenity --error --title="SM64 Plus" \
        --text="Asset extraction failed. Check that your ROM is valid."
    exit 1
fi

export SM64PLUS_SOUND_DIR="$SOUND_DIR"
exec /app/bin/sm64plus "$GFX_DIR" "$@"
```

#### 2c. Pass sound data directory to binary

The binary reads the `SM64PLUS_SOUND_DIR` environment variable. In `main_func()`:
- Check for `SM64PLUS_SOUND_DIR` env var
- Call `load_external_audio()` with that path before audio init

### Phase 3: Flatpak manifest changes

**File: `flatpak/com.github.MorsGames.sm64plus.yml`**

- Build with `make EXTERNAL_DATA=1 VERSION=${VERSION}`
- Remove `cp -r build/${VERSION}_pc/gfx` line (don't ship textures)
- Add `--filesystem=xdg-data/sm64plus:create` to finish-args (user data access)
- Add install commands for extraction tools and data files to `/app/lib/sm64plus/`
- Install `extract-assets.sh` to `/app/bin/`

## Files to modify

| File | Change |
|------|--------|
| `Makefile` | Add `EXTERNAL_DATA` flag, auto-NOEXTRACT, placeholder generation |
| `tools/generate_placeholders.py` | **New** — creates placeholder files from assets.json |
| `sound/sound_data.c` | Conditional pointer vs array based on EXTERNAL_DATA |
| `src/audio/load.c` | Change extern declarations when EXTERNAL_DATA |
| `src/audio/load_sh.c` | Change extern declarations when EXTERNAL_DATA |
| `src/pc/pc_main.c` | Add `load_external_audio()`, read SM64PLUS_SOUND_DIR env var |
| `flatpak/sm64plus-wrapper.sh` | Rewrite for first-run extraction with zenity dialogs |
| `flatpak/extract-assets.sh` | **New** — ROM extraction + sound build pipeline |
| `flatpak/com.github.MorsGames.sm64plus.yml` | Build with EXTERNAL_DATA, ship tools, remove gfx |

## Verification

1. `make EXTERNAL_DATA=1` should succeed without a ROM present
2. The resulting binary should launch and run (with placeholder textures and no audio)
3. Flatpak build should succeed without a ROM
4. Placing `baserom.us.z64` in the data dir and launching should trigger extraction
5. After extraction, the game should have full textures and audio
6. Subsequent launches should skip extraction

## Technical details

### Why textures are safe without ROM at build time

With `CUSTOM_TEXTURES=1`, the Makefile rules (lines 686-691) work like this:
```makefile
$(BUILD_DIR)/%: %.png
    printf "%s%b" "$(patsubst %.png,%,$^)" '\0' > $@

$(BUILD_DIR)/%.inc.c: $(BUILD_DIR)/% %.png
    hexdump -v -e '1/1 "0x%X,"' $< > $@
```

The PNG file content is never read — only its filename is written as a null-terminated string. The `.inc.c` file contains this filename string as hex bytes. At runtime, `gfx_pc.c:856` uses this string to construct a filesystem path and loads the real PNG from the `gfx/` directory.

### Why audio loading from files works

On PC, `osPiStartDma` (`src/pc/ultra_reimplementation.c:17-22`) is:
```c
s32 osPiStartDma(..., uintptr_t devAddr, void *vAddr, size_t nbytes, ...) {
    memcpy(vAddr, (const void *) devAddr, nbytes);
    return 0;
}
```

All audio data access goes through this function, which just copies from the source address. Whether that address points to a compiled-in array or a `malloc`'d buffer loaded from a file makes no difference. The pointer patching in `audio_init()` (load.c:907+) adds base addresses to relative offsets — this arithmetic works identically regardless of where the buffer lives in memory.

### Audio build pipeline for runtime extraction

The extraction script needs to replicate what the Makefile does for sound:
1. Extract AIFF samples from ROM using `disassemble_sound.py`
2. For each AIFF: extract codebook (`aiff_extract_codebook`) and encode ADPCM (`vadpcm_enc`) → `.aifc`
3. Run `assemble_sound.py` with the encoded samples + sound bank JSONs → `sound_data.ctl`, `sound_data.tbl`
4. Run `assemble_sound.py --sequences` with sequence files + bank JSONs → `sequences.bin`, `bank_sets`
5. Ship the resulting 4 binary files to the user's data directory
