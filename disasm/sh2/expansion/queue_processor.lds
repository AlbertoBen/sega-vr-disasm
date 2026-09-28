/* Linker script for the queue processor. */
SECTIONS
{
    . = 0x300C00;  /* ROM file offset 0x300C00 */
    .text : SUBALIGN(2) { *(.text) }
}
