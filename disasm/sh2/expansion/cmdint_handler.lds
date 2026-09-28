/* Linker script for the CMDINT handler. */
SECTIONS
{
    . = 0x300800;  /* ROM file offset 0x300800 */
    .text : SUBALIGN(2) { *(.text) }
}
