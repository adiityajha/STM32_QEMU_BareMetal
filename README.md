# STM32F4 Bare-Metal Boot on QEMU

## Submitted by

| Name | Entry Number |
|-----|-------------|
| Aditya Jha | 2025EET2479 |
| Aman Mongre | 2025EET2488 |


## Course
Embedded Systems – Assignment 1

---
The README file can be viewed in Markdown preview mode in most editors.

VS Code (macOS): Cmd + Shift + V  
VS Code (Windows): Ctrl + Shift + V

Screenshots can be viewed in preview mode.

---

# Introduction

This assignment implements the bare-metal boot sequence of an STM32F4 Cortex-M4 microcontroller running inside the QEMU emulator. The assignment was built and tested on macOS.

The submission covers:

- A hand-written interrupt vector table and Reset_Handler in assembly
- Runtime initialization of the `.data` and `.bss` sections
- A custom linker script that places every section at the correct address
- Semihosting output so the program can print to the host terminal via QEMU
- SysTick timer configuration and interrupt handler
- Full GDB debugging session confirming each of the above

---

# Memory Map 

These are the two memory regions available on the STM32F405 and configured in `linker.ld`.

| Region | Start        | End          | Size   |
|--------|--------------|--------------|--------|
| FLASH  | `0x08000000` | `0x080FFFFF` | 1 MB   |
| SRAM   | `0x20000000` | `0x2001FFFF` | 128 KB |

`_estack` represents the initial stack pointer value. It is placed at the top of RAM (`0x20020000`), which is calculated as `ORIGIN(RAM) + LENGTH(RAM)`. The Cortex-M stack grows downward toward lower memory addresses, so the stack must start from the highest RAM address.

# Linker symbols used by the startup code:

| Symbol    | Value (from map)  | Description                                           |
|-----------|-------------------|-------------------------------------------------------|
| `_estack` | `0x20020000`      | Initial stack pointer, top of RAM                   |
| `_sidata` | `0x0800021c`      | Flash address where `.data` initial values are stored |
| `_sdata`  | `0x20000000`      | Start address of `.data` section in RAM               |
| `_edata`  | `0x20000004`      | End address of `.data` section in RAM                 |
| `_sbss`   | `0x20000004`      | Start address of `.bss` section in RAM                |
| `_ebss`   | `0x2000000c`      | End address of `.bss` section in RAM                  |

---

# QEMU Run and Debug Commands

## Build the Project

```bash
make clean
make
```

This compiles `src/main.c` and `startup/startup_stm32f4.s`, links them with
`ld/linker.ld`, and produces `firmware.elf`, `firmware.bin`, and `firmware.map`.

## Run in QEMU

```bash
make qemu
```

Or manually:

```bash
qemu-system-arm \
  -M olimex-stm32-h405 \
  -kernel firmware.bin \
  -semihosting-config enable=on,target=native \
  -nographic
```

The `-semihosting-config enable=on,target=native` flag is required. Without it,
the `BKPT 0xAB` instruction used for semihosting causes a HardFault instead of
printing to the terminal.

To exit QEMU: press **Ctrl+A then X**.

## Debugging with GDB

Open two terminals.

**Terminal 1 **

```bash
make qemu-gdb
```

Or manually:

```bash
qemu-system-arm \
  -M olimex-stm32-h405 \
  -kernel firmware.bin \
  -semihosting-config enable=on,target=native \
  -S -gdb tcp::3333 \
  -nographic
```

The `-S` flag tells QEMU to halt immediately at reset and wait.

**Terminal 2 – Connect GDB to QEMU**

```bash
arm-none-eabi-gdb firmware.elf
# if pager prompts appear, press c to continue
(gdb) target remote :3333
```
Now we can set breakpoints, step through code, and inspect memory.

---

# Boot Sequence Explanation

1. After reset the Cortex-M4 reads the vector table from the start of flash (`0x08000000`).
2. The first word (`0x20020000`) is loaded into the stack pointer SP.
3. The second word (`0x0800011d`) is loaded into the program counter PC ,the LSB is 1 (Thumb bit). The CPU clears this bit internally and begins execution at address `0x0800011c`, which is the first instruction of `Reset_Handler`.
4. The CPU begins executing `Reset_Handler` at `0x0800011c`.
5. `Reset_Handler` copies the `.data` section word-by-word from flash (`0x0800021c`) to RAM (`0x20000000`) using the `_sidata`, `_sdata`, and `_edata` symbols.
6. `Reset_Handler` zeroes every word of the `.bss` section in RAM (`0x20000004` to `0x2000000c`) using the `_sbss` and `_ebss` symbols.
7. `Reset_Handler` calls `main()` with `bl main`.
8. `main()` prints status messages through semihosting to confirm it was reached and that memory initialization worked.
9. `main()` configures the SysTick timer.
10. The SysTick interrupt fires periodically and `SysTick_Handler` increments the global `systick_count` variable; the main loop detects the change and prints a message through semihosting each time the counter increases.

---

# Linker Script and Map File Explanation

## Memory regions

```
FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
```

## Section placement (from `firmware.map`)

| Section         | Address      | Size   | Notes                                                        |
|-----------------|--------------|--------|--------------------------------------------------------------|
| `.isr_vector`   | `0x08000000` | 64 B   | 16 × 4-byte vectors, placed first in flash                   |
| `.text`         | `0x08000040` | 304 B  | All compiled code including `main`                           |
| `.rodata`       | `0x08000170` | 172 B  | String literals used by `sh_puts`                            |
| `.data` (load)  | `0x0800021c` | 4 B    | Initial value of `initialized` stored here in flash          |
| `.data` (run)   | `0x20000000` | 4 B    | Copied to RAM at startup by `Reset_Handler`                  |
| `.bss`          | `0x20000004` | 8 B    | `uninitialized` (4 B) + `systick_count` (4 B), zeroed at startup |

## .data load address vs run address

The `.data` section has **two addresses**. The *load address* (`0x0800021c`) is where
the initial values are stored in flash inside the firmware image. The *run address*
(`0x20000000`) is where the variables must live in RAM at runtime so they can be
modified. `Reset_Handler` performs the copy between these two addresses before
calling `main()`.

## Flash and RAM usage

- **Flash used:** `0x08000220 − 0x08000000` = **544 bytes** (out of 1 MB)
- **RAM used:**   `0x2000000c − 0x20000000` = **12 bytes** (out of 128 KB)

The vector table sits at `0x08000000` exactly as required by the Cortex-M architecture.

---

# GDB Evidence

All the evidences below are from an actual GDB session.Screenshots are also included .

## Part A – Vector Table and Reset Handler

**Commands used:**

```
(gdb) x/2xw 0x08000000
(gdb) info reg sp pc
```

**GDB log:**

```
(gdb) x/2xw 0x08000000
0x8000000 <g_pfnVectors>:       0x20020000      0x0800011d

(gdb) info reg sp pc
sp             0x20020000          0x20020000
pc             0x800011c           0x800011c <Reset_Handler>
```
**Explanation:**

- The first value in the vector table is `0x20020000`. This is the initial stack pointer (`_estack`), which is the top of RAM.
- The second value is `0x0800011d`. This is the address of `Reset_Handler`. The least significant bit is `1` because Cortex-M processors use Thumb mode.
- When the CPU loads this address, it clears the last bit and starts executing at `0x0800011c`.
- The register output confirms this:  
  - `sp = 0x20020000` → stack pointer correctly loaded from the vector table  
  - `pc = 0x0800011c` → program counter pointing to `Reset_Handler`

This confirms that the vector table is correctly placed at the start of flash and that the processor begins execution at `Reset_Handler` after reset.

---

## Part B – Runtime Initialization (.data and .bss)

A breakpoint was placed at `main()` and execution was continued so that
`Reset_Handler` ran completely first. The global variables were then inspected.

**Commands used:**

```
(gdb) break main
(gdb) continue
(gdb) print initialized
(gdb) print uninitialized
```

**GDB log:**

```
(gdb) break main
Breakpoint 1 at 0x80000ae: file src/main.c, line 56.
(gdb) continue
Continuing.

Breakpoint 1, main () at src/main.c:56
56          sh_puts("\r\n STM32F4 Bare-Metal Boot Success \r\n");
(gdb) print initialized
$1 = 123
(gdb) print uninitialized
$2 = 0
(gdb) 

```

**Explanation:**

- `initialized == 123` confirms the `.data` copy loop worked. The value 123 was
  stored in flash at `0x0800021c` and was copied to RAM at `0x20000000` by
  `Reset_Handler` before `main()` was called.
- `uninitialized == 0` confirms the `.bss` zero loop worked. The variable has no
  initializer in C so it was zeroed by the startup code.

---

## Part C – Linker Script and Memory Layout

The linker script (`ld/linker.ld`) defines the memory layout of the program.
It specifies the FLASH and RAM regions and tells the linker where each section
of the program should be placed.

The `.isr_vector` section is placed at the beginning of flash (`0x08000000`)
because the Cortex-M processor reads the vector table from this address during
reset.

The `.data` section uses `AT > FLASH`. This means the initial values of the
variables are stored in flash, but the variables themselves run in RAM at
runtime. During startup, `Reset_Handler` copies these values from flash to RAM.

The linker also generates a map file (`firmware.map`) using the flag
`-Wl,-Map=firmware.map`. This file shows the exact memory addresses of all
sections and symbols, which confirms that the program was placed in memory
correctly.
---

## Part D – Semihosting Output

Semihosting is implemented in `src/semihosting.h` using `BKPT 0xAB`. QEMU
intercepts this specific breakpoint number and treats it as a host I/O request
rather than a debug halt. The `SYS_WRITE0` (opcode `0x04`) operation prints a
null-terminated string to the terminal.

QEMU must be run with `-semihosting-config enable=on,target=native`.

**Program Output:**

```
STM32F4 Bare-Metal Boot Success 
Memory Init Verification: SUCCESS
SysTick Interrupts Active
SysTick Interrupt detected!
SysTick Interrupt detected!
SysTick Interrupt detected!
SysTick Interrupt detected!
SysTick Interrupt detected!
SysTick Interrupt detected!

...
```

This output proves that `main()` was reached, that both memory sections were initialized correctly, and that SysTick interrupts are firing.

---

## Part E – SysTick Interrupt Verification

The SysTick timer is initialized in `systick_init()` using the maximum reload
value (`0x00FFFFFF`). The processor clock is used and the interrupt is enabled
by setting the required bits in the `SYSTICK_CTRL` register.

The interrupt handler `SysTick_Handler` is implemented in the startup file.
Every time the interrupt fires, it increments the global variable
`systick_count`.

The variable `systick_count` is declared as `volatile` in `main.c` so the
compiler always reads its latest value from memory.

To verify that the interrupt was working, a breakpoint was placed inside
`SysTick_Handler`. The value of `systick_count` was printed multiple times
while continuing execution.

**Commands used:**

```
(gdb) break SysTick_Handler
(gdb) monitor system_reset
(gdb) continue
(gdb) print systick_count
(gdb) continue
(gdb) print systick_count
(gdb) continue
(gdb) print systick_count
```

**GDB log:**

```
(gdb) break SysTick_Handler
Breakpoint 2 at 0x800015c: file startup/startup_stm32f4.s, line 138.
(gdb) continue
Continuing.

Breakpoint 2, SysTick_Handler () at startup/startup_stm32f4.s:138
138     ldr r0, =systick_count    /* load address of the counter variable */
(gdb) print systick_count
$3 = 0
(gdb) continue
Continuing.

Breakpoint 2, SysTick_Handler () at startup/startup_stm32f4.s:138
138     ldr r0, =systick_count    /* load address of the counter variable */
(gdb) print systick_count
$4 = 1
(gdb) continue
Continuing.

Breakpoint 2, SysTick_Handler () at startup/startup_stm32f4.s:138
138     ldr r0, =systick_count    /* load address of the counter variable */
(gdb) print systick_count
$5 = 2
(gdb) 
```

**Explanation:**

- A breakpoint was placed inside `SysTick_Handler`.
- Each time the SysTick interrupt fires, execution stops at the handler.
- The value of `systick_count` was printed after each interrupt.
From the log we can see:
- First time → `systick_count = 0`
- Second time → `systick_count = 1`
- Third time → `systick_count = 2`

This shows that the interrupt handler is running and the variable `systick_count` is increasing by 1 every time the SysTick interrupt occurs.
---

# File Structure

```
stm32_qemu_baremetal_aditya_jha_aman_mongre/
├── src/
│   ├── main.c
│   └── semihosting.h
├── startup/
│   └── startup_stm32f4.s
├── ld/
│   └── linker.ld
├── Makefile
├── README.md
└── firmware.map
```

---


# Screenshots

The following screenshots show the GDB session used to verify the boot process.

<img width="1280" height="878" alt="image" src="https://github.com/user-attachments/assets/0e6fba0b-93d1-4e95-a497-517a9eb04ebd" />
<img width="1280" height="640" alt="image" src="https://github.com/user-attachments/assets/2bc66390-54dd-4b63-8b42-f2b6f1e0d5c4" />
<img width="1280" height="885" alt="image" src="https://github.com/user-attachments/assets/132ee555-1d4b-46fd-9fe2-fc26cf8e59cd" />



# Conclusion

This assignment demonstrates the full bare-metal boot sequence of a Cortex-M4
processor. The vector table, Reset_Handler, memory initialization, linker script,
semihosting output, and SysTick interrupt were all implemented from scratch without
any vendor library. GDB evidence confirms that every stage of the boot sequence —
SP initialization, PC jump to Reset_Handler, .data copy, .bss zeroing, and SysTick
interrupt delivery works as expected.
