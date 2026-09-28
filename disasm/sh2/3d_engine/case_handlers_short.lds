/* Linker script for the switch case handlers short function. */
SECTIONS
{
    . = 0x23070;  /* ROM file offset 0x23070 */
    .text : SUBALIGN(2) { *(.text) }
}
