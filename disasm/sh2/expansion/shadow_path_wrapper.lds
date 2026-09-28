/* Linker script for the shadow-path wrapper. */
SECTIONS
{
    . = 0x300400;  /* ROM file offset 0x300400 */
    .text : SUBALIGN(2) { *(.text) }
}
