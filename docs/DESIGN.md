# Design

The port keeps the original Z80 game logic, map progression and PSG sound. V9990 P1 plane B holds terrain; plane A holds the HUD and masks sprites outside the playfield. Hardware sprites use the original depth order. Editable indexed PNGs, TMX maps and four palettes are compiled into an ASCII16 cartridge. The original MSX video output retains boot credits; all subsequent game presentation uses V9990.
