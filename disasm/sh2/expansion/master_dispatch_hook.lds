/* Linker script for the master dispatch hook. */
SECTIONS
{
    . = 0x300050;  /* ROM file offset 0x300050 */
    .text : SUBALIGN(2) { *(.text) }
}
