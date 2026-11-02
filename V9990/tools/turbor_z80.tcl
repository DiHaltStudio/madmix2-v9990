# Session-local turbo R policy. S1990 R6 bit5 selects the actual Z80 CPU.
# https://github.com/openMSX/openMSX/blob/master/src/MSXS1990.cc
if {{S1990 regs} ni [debug list]} {error "This target requires a turbo R with S1990"}
set ::tr_native 0
proc port_force_z80 {} {
    set r [debug read {S1990 regs} 6]
    debug write {S1990 regs} 6 [expr {$r | 0x20}]
}
port_force_z80
debug set_bp 0x4010 {!$::tr_native && [peek16 0x4000]==0x4241} {port_force_z80}
debug set_bp 0x1100 {[peek16 0x1061]==0x1100 && [debug read memory 0x1100]==195} {
    port_force_z80
    set ::tr_native 1
    # V9990 supplies its own PAL audio/display clock. Leave the MSX VDP alone.
}
debug set_bp 0x388F {$::tr_native} {
    if {!([debug read {S1990 regs} 6]&0x20)} {error "R800 unexpectedly active during gameplay"}
}
