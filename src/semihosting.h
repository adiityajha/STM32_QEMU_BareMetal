/*
 * semihosting.h
 *
 * Minimal semihosting so the bare-metal program can print to the
 * host terminal via QEMU. No real UART available in the QEMU STM32 model
 * so this is the easiest way to get any output at all.
 *
 * Works by executing BKPT 0xAB -- QEMU intercepts this specific breakpoint
 * number and treats it as a semihosting request rather than a debug halt.
 *
 * QEMU needs: -semihosting-config enable=on,target=native
 * Without that flag the BKPT causes a HardFault instead.
 */

#pragma once   /* prevents this header from being included multiple times */


/* ---------------------------------------------------------------------------
 * Semihosting operation code used in this project.
 * SYS_WRITE0 prints a null-terminated string to the console.
 * ---------------------------------------------------------------------------*/
#define SEMIHOSTING_SYS_WRITE0  0x04


/* semihosting_call - issue a semihosting request to QEMU.
 *
 * ARM semihosting ABI: r0 = operation code, r1 = argument pointer.
 * BKPT 0xAB is the trigger; QEMU handles it and returns result in r0.
 *
 * The clobber list (r0, r1, memory) stops the compiler from assuming
 * those registers still hold their old values after the asm block. */
static inline int semihosting_call(int reason, void *arg)
{
    int value;   /* return value from the semihosting operation */

    __asm volatile (
        "mov r0, %1\n"     /* move reason code into r0 */
        "mov r1, %2\n"     /* move argument pointer into r1 */
        "bkpt 0xAB\n"      /* trigger semihosting call */
        "mov %0, r0\n"     /* return value from r0 */
        : "=r"(value)
        : "r"(reason), "r"(arg)
        : "r0", "r1", "memory"
    );

    return value;
}


/* sh_puts - print a null-terminated string, used throughout main.c */
static inline void sh_puts(const char *s)
{
    semihosting_call(SEMIHOSTING_SYS_WRITE0, (void*)s);
}

/* End of semihosting.h */