# Building

Requires Python 3, Pillow (`pip install -r requirements.txt` in a virtual environment), SJASM and an original-game workspace. For the manuals, install Tectonic and DejaVu Sans fonts.

`make build ORIGINAL_DIR=/path/to/private/workspace` links private resources and builds a 1 MiB ASCII16 ROM at `V9990/build/madmix2-v99990.rom`. The private workspace must contain:

- `MSX/original/`: the original Mad Mix 2 CAS.
- `MSX/build/`: the byte-faithful `game.bin`, `loader.bin`, `opening.bin`, `intro.bin`, `stage.bin` and cartridge bridge images reconstructed from that CAS.
- `V9990/assets/music/`, `sfx/`, `opening/`: original PSG captures and opening art needed by the renderer build.

These private files are linked locally and excluded from Git. `make run` uses a downloaded release ROM and needs none of them. `make manual` builds the two PDF manuals. `make release` copies the built ROM and manuals to `release/`.
