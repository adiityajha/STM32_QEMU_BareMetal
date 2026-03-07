/* ===========================================================================
 * linker.ld
 *
 * This linker script defines the memory layout of the STM32F4 program.
 * It tells the linker where each section of the program should be placed
 * in memory.
 *
 * FLASH : used for program code and constant data
 * RAM   : used for variables, stack, and runtime memory
 *
 * The symbols defined here are used by the startup code to initialize
 * the program before main() starts.
 * ===========================================================================*/


/* The program starts execution from Reset_Handler */
ENTRY(Reset_Handler)


/* ---------------------------------------------------------------------------
 * Define memory regions available on STM32F4
 *
 * FLASH → program code and constants
 * RAM   → variables and stack
 * ---------------------------------------------------------------------------*/
MEMORY
{
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
}


/* ---------------------------------------------------------------------------
 * _estack
 *
 * This symbol defines the initial stack pointer value.
 * The stack starts at the top of RAM and grows downward.
 * ---------------------------------------------------------------------------*/
_estack = ORIGIN(RAM) + LENGTH(RAM);


/* ===========================================================================
 * Section placement
 * ===========================================================================*/
SECTIONS
{

/* ---------------------------------------------------------------------------
 * Interrupt Vector Table
 *
 * This must be placed at the very start of flash memory because
 * the Cortex-M CPU reads the first two entries after reset:
 *
 *  Address 0x08000000 → initial stack pointer
 *  Address 0x08000004 → Reset_Handler address
 * ---------------------------------------------------------------------------*/
.isr_vector :
{
    . = ALIGN(4);
    KEEP(*(.isr_vector))   /* keep vector table from startup file */
    . = ALIGN(4);
} > FLASH


/* ---------------------------------------------------------------------------
 * .text section
 *
 * Contains the program instructions (compiled code).
 * This includes Reset_Handler, main(), and other functions.
 * ---------------------------------------------------------------------------*/
.text :
{
    . = ALIGN(4);
    *(.text)
    *(.text*)
    *(.glue_7)
    *(.glue_7t)
    . = ALIGN(4);
} > FLASH


/* ---------------------------------------------------------------------------
 * .rodata section
 *
 * Contains read-only data like constant variables and strings.
 * Example: string literals used in printf or sh_puts().
 * ---------------------------------------------------------------------------*/
.rodata :
{
    . = ALIGN(4);
    *(.rodata)
    *(.rodata*)
    . = ALIGN(4);
} > FLASH


/* ---------------------------------------------------------------------------
 * .data section
 *
 * Global variables with initial values go here.
 *
 * Their initial values are stored in FLASH in the program image,
 * but at runtime the variables must exist in RAM.
 *
 * Reset_Handler copies these values from flash to RAM.
 * ---------------------------------------------------------------------------*/

_sidata = LOADADDR(.data);   /* flash address where .data initial values are stored */

.data :
{
    . = ALIGN(4);

    _sdata = .;              /* start of .data in RAM */

    *(.data)
    *(.data*)

    . = ALIGN(4);
    _edata = .;              /* end of .data in RAM */

} > RAM AT > FLASH


/* ---------------------------------------------------------------------------
 * .bss section
 *
 * Global variables without initialization go here.
 * These variables must start with value 0.
 *
 * Reset_Handler clears this memory before main() starts.
 * ---------------------------------------------------------------------------*/
.bss :
{
    . = ALIGN(4);

    _sbss = .;               /* start of .bss */

    *(.bss)
    *(.bss*)
    *(COMMON)

    . = ALIGN(4);
    _ebss = .;               /* end of .bss */

} > RAM

}

/* End of linker script */