PYTHON ?= python3
SJASM ?= sjasm
OPENMSX ?= openmsx
ORIGINAL_DIR ?= ../madmixgame2_v9990
TECTONIC ?= tectonic
export SJASM
.PHONY: all build prepare-original run run-turboR release manual clean help
all: build
prepare-original:
	ORIGINAL_DIR="$(ORIGINAL_DIR)" $(PYTHON) tools/prepare_original.py
build: prepare-original
	$(PYTHON) V9990/tools/build_port.py
release: build
	$(PYTHON) V9990/tools/update_release.py
manual:
	$(PYTHON) V9990/tools/prepare_manual.py
	$(PYTHON) V9990/tools/manual_images.py V9990/docs/manual
	$(TECTONIC) V9990/docs/manual/manual-en.tex
	$(TECTONIC) V9990/docs/manual/manual-es.tex
run:
	@test -f release/madmix2-v99990.rom || { echo 'Download v1.0 ROM into release/ or run make build'; exit 1; }
	$(OPENMSX) -machine Sony_HB-10P -ext gfx9000 -cart release/madmix2-v99990.rom -romtype ASCII16
run-turboR:
	@test -f release/madmix2-v99990.rom || { echo 'Download v1.0 ROM into release/ or run make build'; exit 1; }
	$(OPENMSX) -machine Panasonic_FS-A1GT -ext gfx9000 -cart release/madmix2-v99990.rom -romtype ASCII16 -script V9990/tools/turbor_z80.tcl
clean:
	rm -rf V9990/build
help:
	@echo 'make build ORIGINAL_DIR=/path/to/private/workspace'
	@echo 'make release: build and copy ROM/manuals to release/'
	@echo 'make run: play release ROM without building'
