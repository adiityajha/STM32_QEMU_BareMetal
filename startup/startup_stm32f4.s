/* ===========================================================================
 * startup_stm32f4.s
 *
 * This file contains the startup code for STM32F4 running on QEMU.
 * When the microcontroller resets, the CPU does not directly start from
 * main(). Instead it first reads the vector table and then jumps to
 * Reset_Handler. From there we prepare the memory and finally call main().
 *
 * Tasks done in this file:
 * 1. Define the interrupt vector table at the beginning of flash memory.
 * 2. Set the initial stack pointer.
 * 3. Copy .data section from flash to RAM.
 * 4. Clear the .bss section.
 * 5. Call main().
 * 6. Provide default handlers for faults and exceptions.
 *
 * Memory layout used:
 * FLASH : 0x08000000 - 0x080FFFFF
 * RAM   : 0x20000000 - 0x2001FFFF
 * ===========================================================================*/


/* --------------------------------------------------------------------------
 * Assembly configuration for Cortex-M4
 * --------------------------------------------------------------------------*/
    .syntax unified        /* Use unified assembly syntax                   */
    .cpu cortex-m4         /* Target processor is Cortex-M4                 */
    .thumb                 /* Cortex-M only supports Thumb instructions     */
    .fpu fpv4-sp-d16       /* tells assembler to accept FPU register names  */


/* --------------------------------------------------------------------------
 * Symbols coming from linker.ld
 * (the linker fills these in when it combines all .o files)
 * --------------------------------------------------------------------------*/
    .extern _estack
    .extern _sidata
    .extern _sdata
    .extern _edata
    .extern _sbss
    .extern _ebss


/* symbols that the linker and other files need to see */
    .global g_pfnVectors
    .global Reset_Handler
    .global SysTick_Handler


/* ==========================================================================
 * Vector Table
 *
 * The vector table must be placed at the start of flash memory.
 * When the CPU resets it does two automatic operations:
 *
 * 1. Load stack pointer from address 0x08000000
 * 2. Load program counter from address 0x08000004
 *
 * So the first entry must be the stack pointer and the second entry
 * must be the Reset_Handler address.
 * ==========================================================================*/
.section .isr_vector, "a", %progbits
.type g_pfnVectors, %object

g_pfnVectors:

    .word _estack            /* Initial stack pointer (top of RAM)        */
    .word Reset_Handler      /* Reset handler (program entry point)       */
    .word NMI_Handler
    .word HardFault_Handler
    .word MemManage_Handler
    .word BusFault_Handler
    .word UsageFault_Handler
    .word 0                  /* Reserved                                  */
    .word 0                  /* Reserved                                  */
    .word 0                  /* Reserved                                  */
    .word 0                  /* Reserved                                  */
    .word SVC_Handler
    .word DebugMon_Handler
    .word 0                  /* Reserved                                  */
    .word PendSV_Handler
    .word SysTick_Handler    /* SysTick interrupt                          */

.size g_pfnVectors, .-g_pfnVectors


/* ==========================================================================
 * Reset_Handler
 *
 * This is the first function executed after reset.
 * Before calling main() we must prepare the memory.
 *
 * Steps done here:
 * 1. Copy initialized variables (.data) from flash to RAM
 * 2. Set all uninitialized variables (.bss) to zero
 * 3. Call main()
 * ==========================================================================*/

.section .text.Reset_Handler, "ax", %progbits
.type Reset_Handler, %function

Reset_Handler:

/* Step 1: copy .data from flash to RAM.
 * Variables like "int x = 5" have their initial value stored in flash
 * but need to be in RAM at runtime so they can be modified.
 * We copy them word by word using the linker symbols as boundaries. */

    ldr r0, =_sidata      /* Source address in flash                      */
    ldr r1, =_sdata       /* Destination start address in RAM             */
    ldr r2, =_edata       /* End of .data section in RAM                  */

data_copy_loop:
    cmp r1, r2            /* check if destination pointer reached end       */
    bhs data_copy_done    /* bhs = unsigned >=  (bge is signed, wrong here  */
                          /* because RAM addresses like 0x20000000 have MSB */
                          /* set and signed compare would treat them wrong) */
    ldr r3, [r0], #4      /* load word from flash, advance source pointer   */
    str r3, [r1], #4      /* store word to RAM, advance dest pointer        */
    b data_copy_loop

data_copy_done:


/* Step 2: zero out .bss
 * C says globals without an initialiser must start as zero.
 * They dont have values stored in flash so we just fill the RAM region with 0. */

    ldr r1, =_sbss
    ldr r2, =_ebss
    movs r3, #0

bss_zero_loop:
    cmp r1, r2            /* are we past the end of .bss?                  */
    bhs bss_zero_done     /* unsigned >= so addresses compare correctly     */
    str r3, [r1], #4      /* write zero word and advance pointer            */
    b bss_zero_loop

bss_zero_done:


/* --------------------------------------------------------------------------
 * Step 3 : Call main()
 * Now memory is ready so we can start the C program.
 * --------------------------------------------------------------------------*/

    bl main


/* --------------------------------------------------------------------------
 * If main() ever returns we just stay in an infinite loop.
 * In embedded programs main() usually never returns.
 * --------------------------------------------------------------------------*/

inf_loop:
    b inf_loop

.size Reset_Handler, .-Reset_Handler



/* ==========================================================================
 * SysTick Handler
 *
 * This interrupt runs every time the SysTick timer expires.
 * We simply increase a counter so we can see that interrupts
 * are working correctly.
 * ==========================================================================*/

.extern systick_count

.section .text.SysTick_Handler, "ax", %progbits
.type SysTick_Handler, %function
/* NOTE: SysTick_Handler is NOT .weak because this IS the real implementation.
 * .weak is only correct for Default_Handler aliases so users can override them.
 * Marking the actual handler weak would allow a linker accident to silently
 * discard it if any other translation unit happened to define a strong symbol
 * with the same name. Keep it strong. */

SysTick_Handler:

    ldr r0, =systick_count    /* load address of counter variable into r0  */
    ldr r1, [r0]              /* read current counter value                */
    adds r1, r1, #1           /* increment by 1                           */
    str r1, [r0]              /* write new value back to RAM               */
    bx lr                     /* return from interrupt handler             */

.size SysTick_Handler, .-SysTick_Handler



/* ==========================================================================
 * Default Handler
 *
 * If any unexpected interrupt happens, the CPU will come here.
 * We simply stay in an infinite loop so that the error can be
 * detected during debugging.
 * ==========================================================================*/

.section .text.Default_Handler, "ax", %progbits
.type Default_Handler, %function

Default_Handler:
    b Default_Handler

.size Default_Handler, .-Default_Handler



/* Weak aliases so user code can override these handlers if needed */

.weak NMI_Handler
.thumb_set NMI_Handler, Default_Handler

.weak HardFault_Handler
.thumb_set HardFault_Handler, Default_Handler

.weak MemManage_Handler
.thumb_set MemManage_Handler, Default_Handler

.weak BusFault_Handler
.thumb_set BusFault_Handler, Default_Handler

.weak UsageFault_Handler
.thumb_set UsageFault_Handler, Default_Handler

.weak SVC_Handler
.thumb_set SVC_Handler, Default_Handler

.weak DebugMon_Handler
.thumb_set DebugMon_Handler, Default_Handler

.weak PendSV_Handler
.thumb_set PendSV_Handler, Default_Handler

/* End of startup file */