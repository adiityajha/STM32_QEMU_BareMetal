/*
 * main.c
 *
 * Main application for STM32F4 bare-metal assignment running on QEMU.
 * startup_stm32f4.s calls this after copying .data and zeroing .bss.
 *
 * Shows three things:
 *   1. runtime init check (.data and .bss)
 *   2. semihosting output so we can actually see something
 *   3. SysTick interrupt working
 */

#include <stdint.h>
#include "semihosting.h"

/* these two globals are used to check that Reset_Handler did its job.
 * 'initialized' should be 123 (copied from flash by the .data loop)
 * 'uninitialized' should be 0 (zeroed by the .bss loop) */
int initialized = 123;   /* should remain 123 after startup */
int uninitialized;       /* should become 0 after startup   */


/* counter incremented by SysTick_Handler each time the timer fires.
 * must be volatile otherwise the compiler might cache it in a register
 * and the while loop would never see it change */
volatile uint32_t systick_count = 0;


/* SysTick register addresses - these are Cortex-M core peripherals
 * so same addresses on every ARM chip, not STM32-specific */
#define SYSTICK_BASE    0xE000E010UL

#define SYSTICK_CTRL    (*(volatile uint32_t*)(SYSTICK_BASE + 0x00))
#define SYSTICK_LOAD    (*(volatile uint32_t*)(SYSTICK_BASE + 0x04))
#define SYSTICK_VAL     (*(volatile uint32_t*)(SYSTICK_BASE + 0x08))


/* Control register bit masks */
#define SYSTICK_CTRL_ENABLE    (1U << 0)
#define SYSTICK_CTRL_TICKINT   (1U << 1)
#define SYSTICK_CTRL_CLKSOURCE (1U << 2)


/*
 * systick_init - set up SysTick timer to generate periodic interrupts.
 * The reload value is the 24-bit max. Exact timing doesnt matter much in
 * QEMU, we just need the interrupt to fire so we can observe it.
 */
static void systick_init(void)
{
    /* Set reload value (24-bit maximum value) */
    SYSTICK_LOAD = 0x00FFFFFFU;

    /* Reset the current counter value */
    SYSTICK_VAL = 0U;

    /* Enable SysTick with interrupt and processor clock */
    SYSTICK_CTRL = SYSTICK_CTRL_CLKSOURCE
                 | SYSTICK_CTRL_TICKINT
                 | SYSTICK_CTRL_ENABLE;
}


/* main - called by Reset_Handler after memory init is done */
int main(void)
{
    /* Print message to show that main() was reached */
    sh_puts("Boot OK\r\n");


    /* ---------------------------------------------------------------
     * Check if .data and .bss sections were initialized correctly.
     * ---------------------------------------------------------------*/
    if (initialized == 123 && uninitialized == 0)
    {
        sh_puts("Data/BSS OK: initialized=123, uninitialized=0\r\n");
    }
    else
    {
        sh_puts("ERROR: Data/BSS init FAILED\r\n");
    }


    /* ---------------------------------------------------------------
     * Configure SysTick timer.
     * After this the interrupt will start firing automatically.
     * ---------------------------------------------------------------*/
    systick_init();

    sh_puts("SysTick enabled – entering main loop\r\n");


    /* ---------------------------------------------------------------
     * Main loop
     * The loop keeps checking the systick counter and prints a
     * message whenever it increases.
     * ---------------------------------------------------------------*/
    uint32_t last_count = 0;

   while (1)
{
    uint32_t current = systick_count;

    if (current != last_count)
    {
        last_count = current;
        sh_puts("SysTick fired\r\n");
    }

    __asm volatile("wfi");   /* volatile prevents the compiler from removing this sleep
                              * instruction as a dead-code optimisation. Without volatile,
                              * -O1 or higher can legally delete an asm with no outputs. */
}

    return 0;
}

/* End of main.c */