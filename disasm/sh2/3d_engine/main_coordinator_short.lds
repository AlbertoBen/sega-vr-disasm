/* Linker script for the main coordinator short function. */
SECTIONS
{
    . = 0x23024;  /* ROM file offset 0x23024 */
    .text : SUBALIGN(2) { *(.text) }
}
