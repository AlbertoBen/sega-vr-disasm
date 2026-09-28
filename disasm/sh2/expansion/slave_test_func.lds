/* Linker script for the slave test function. */
SECTIONS
{
    . = 0x300280;  /* ROM file offset 0x300280 */
    .text : SUBALIGN(2) { *(.text) }
}
