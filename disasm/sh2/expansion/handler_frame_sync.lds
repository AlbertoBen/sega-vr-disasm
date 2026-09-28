/* Linker script for the frame-sync handler. */
SECTIONS
{
    . = 0x300028;  /* ROM file offset 0x300028 */
    .text : SUBALIGN(2) { *(.text) }
}
