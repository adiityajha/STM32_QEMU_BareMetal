# STM32F4 Bare-Metal Boot on QEMU

## Author
Aditya Jha

## Course
Embedded Systems – Assignment 1

---

# Introduction

This assignment implements the bare-metal boot sequence of an STM32F4 Cortex-M4 microcontroller running inside the QEMU emulator.Built and tested on macOS.

The submission covers:

- A hand-written interrupt vector table and Reset_Handler in assembly
- Runtime initialization of the `.data` and `.bss` sections
- A custom linker script that places every section at the correct address
- Semihosting output so the program can print to the host terminal via QEMU
- SysTick timer configuration and interrupt handler
- Full GDB debugging session confirming each of the above

---

# Memory Map Used

These are the two memory regions available on the STM32F405 and configured in `linker.ld`.

| Region | Start        | End          | Size   |
|--------|--------------|--------------|--------|
| FLASH  | `0x08000000` | `0x080FFFFF` | 1 MB   |
| SRAM   | `0x20000000` | `0x2001FFFF` | 128 KB |

`_estack` represents the initial stack pointer value. It is placed at the top of RAM (0x20020000), which is calculated as ORIGIN(RAM) + LENGTH(RAM). The Cortex-M stack grows downward toward lower memory addresses, so the stack must start from the highest RAM address.

# Linker symbols used by the startup code:

| Symbol   | Value (from map) | Description                                      |
|----------|------------------|--------------------------------------------------|
| `_estack` | `0x20020000` | Initial stack pointer — top of RAM |
| `_sidata` | `0x08000208` | Flash address where `.data` initial values are stored |
| `_sdata`  | `0x20000000` | Start address of `.data` section in RAM |
| `_edata`  | `0x20000004` | End address of `.data` section in RAM |
| `_sbss`   | `0x20000004` | Start address of `.bss` section in RAM |
| `_ebss`   | `0x2000000C` | End address of `.bss` section in RAM |
---

# QEMU Run and Debug Commands


## Build the Project

```bash
make all
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

**Terminal 1 – Start QEMU paused, waiting for GDB**

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
if asked something like  q to quit, c to continue without paging--
then press c
(gdb) target remote :3333
```

From here we can set breakpoints, inspect registers and memory, and step through the startup code as shown in the sections below.

---

# Boot Sequence Explanation

1. After reset the Cortex-M4 reads the vector table from the start of flash (`0x08000000`).
2. The first word (`0x20020000`) is loaded into the stack pointer SP.
3. The second word (`0x0800011d`) is loaded into the program counter PC — the LSB is 1 (Thumb bit) which the CPU strips off before jumping, landing at `0x0800011c`.
4. The CPU begins executing `Reset_Handler` at `0x0800011c`.
5. `Reset_Handler` copies the `.data` section word-by-word from flash (`0x08000208`) to RAM (`0x20000000`) using the `_sidata`, `_sdata`, and `_edata` symbols.
6. `Reset_Handler` zeroes every word of the `.bss` section in RAM (`0x20000004` to `0x2000000C`) using the `_sbss` and `_ebss` symbols.
7. `Reset_Handler` calls `main()` with `bl main`.
8. `main()` prints status messages through semihosting to confirm it was reached and that memory initialization worked.
9. `main()` configures the SysTick timer (24-bit reload, processor clock, interrupt enabled).
10. The SysTick interrupt fires periodically and `SysTick_Handler` increments `systick_count`; the main loop prints `SysTick fired` each time the counter changes.

---

# Linker Script and Map File Explanation

## Memory regions

```
FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
```

## Section placement (from `firmware.map`)

| Section      | Address      | Size  | Notes                                       |
|--------------|--------------|-------|---------------------------------------------|
| `.isr_vector`| `0x08000000` | 64 B  | 16 × 4-byte vectors, placed first in flash  |
| `.text`      | `0x08000040` | 304 B | All compiled code including `main`          |
| `.rodata`    | `0x08000170` | 152 B | String literals used by `sh_puts`           |
| `.data` (load)| `0x08000208`| 4 B   | Initial value of `initialized` stored here in flash |
| `.data` (run)| `0x20000000` | 4 B   | Copied to RAM at startup by `Reset_Handler` |
| `.bss`       | `0x20000004` | 8 B   | `uninitialized` (4 B) + `systick_count` (4 B), zeroed at startup |

## .data load address vs run address

The `.data` section has **two addresses**. The *load address* (`0x08000208`) is where
the initial values are stored in flash inside the firmware image. The *run address*
(`0x20000000`) is where the variables must live in RAM at runtime so they can be
modified. `Reset_Handler` performs the copy between these two addresses before
calling `main()`.

## Flash and RAM usage

- **Flash used:** `0x0800020C − 0x08000000` = **524 bytes** (out of 1 MB)
- **RAM used:**   `0x2000000C − 0x20000000` = **12 bytes** (out of 128 KB)

The vector table sits at `0x08000000` exactly as required by the Cortex-M architecture.

---

# GDB Evidence

## Part A – Vector Table and Reset Handler

The vector table `g_pfnVectors` is placed at the start of flash by the linker
script section `.isr_vector > FLASH`. The first entry is `_estack` (initial SP)
and the second is `Reset_Handler`.

GDB was connected to QEMU immediately after reset (before any code ran) to
verify the vector table contents and initial register state.

**Commands used:**

```
(gdb) target remote :3333
(gdb) x/2xw 0x08000000
(gdb) info reg sp pc
```

**GDB log:**

```
(gdb) x/2xw 0x08000000
0x8000000 <g_pfnVectors>:    0x20020000    0x0800011d

(gdb) info reg sp pc
sp    0x20020000    0x20020000
pc    0x800011c     0x800011c <Reset_Handler>
```

The screenshot shows:

0x20020000 at 0x08000000 — correct initial stack pointer (top of 128 KB RAM)
0x0800011d at 0x08000004 — reset vector with Thumb bit set (LSB = 1)
SP = 0x20020000, PC = 0x0800011c — CPU stripped the Thumb bit and is sitting at the first instruction of Reset_Handler



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
Breakpoint 1 at 0x80000ae: file src/main.c, line 68.
(gdb) continue
Continuing.
Breakpoint 1, main () at src/main.c:68
68          sh_puts("Boot OK\r\n");

(gdb) print initialized
$1 = 123
(gdb) print uninitialized
$2 = 0
```

**Explanation:**

- `initialized == 123` confirms the `.data` copy loop worked. The value 123 was
  stored in flash at `0x08000208` and was copied to RAM at `0x20000000` by
  `Reset_Handler` before `main()` was called.
- `uninitialized == 0` confirms the `.bss` zero loop worked. The variable has no
  initializer in C so it was zeroed by the startup code.

---

## Part C – Linker Script and Memory Layout

The linker script is in `ld/linker.ld`. It defines the FLASH and RAM regions,
places `.isr_vector` first in flash, and uses `AT > FLASH` on `.data` so the
initial values are stored in flash but the run-time address is in RAM.

The map file `firmware.map` was generated by the linker with `-Wl,-Map=firmware.map`
and confirms all placements. See the **Linker Script and Map File Explanation**
section above for the full breakdown including load vs run addresses and flash/RAM
usage numbers.

---

## Part D – Semihosting Output

Semihosting is implemented in `src/semihosting.h` using `BKPT 0xAB`. QEMU
intercepts this specific breakpoint number and treats it as a host I/O request
rather than a debug halt. The `SYS_WRITE0` (opcode `0x04`) operation prints a
null-terminated string to the terminal.

QEMU must be run with `-semihosting-config enable=on,target=native`.

**Expected terminal output:**

```
Boot OK
Data/BSS OK: initialized=123, uninitialized=0
SysTick enabled – entering main loop
SysTick fired
SysTick fired
SysTick fired
...
```

This output proves that `main()` was reached, that both memory sections were
initialized correctly, and that SysTick interrupts are firing.

---

## Part E – SysTick Interrupt Verification

The SysTick timer is configured in `systick_init()` with the 24-bit maximum
reload value (`0x00FFFFFF`), using the processor clock. Both the counter enable
bit and the interrupt enable bit are set in `SYSTICK_CTRL`.

`SysTick_Handler` is implemented in the startup file. It increments the global
`systick_count` variable which is declared `volatile` in `main.c` so the compiler
cannot cache it.

To verify the handler was actually running, a breakpoint was placed inside it and
`systick_count` was printed across multiple firings.

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
Breakpoint 2 at 0x800015c: file startup/startup_stm32f4.s, line 184.

(gdb) monitor system_reset
(gdb) continue
Continuing.
Breakpoint 1, main () at src/main.c:68
68          sh_puts("Boot OK\r\n");

(gdb) print systick_count
$3 = 0

(gdb) continue
Continuing.
Breakpoint 2, SysTick_Handler () at startup/startup_stm32f4.s:184
184         ldr r0, =systick_count

(gdb) print systick_count
$4 = 0

(gdb) continue
Continuing.
Breakpoint 2, SysTick_Handler () at startup/startup_stm32f4.s:184
184         ldr r0, =systick_count

(gdb) print systick_count
$5 = 1

(gdb) continue
Continuing.
Breakpoint 2, SysTick_Handler () at startup/startup_stm32f4.s:184
184         ldr r0, =systick_count

(gdb) print systick_count
$6 = 2
```

**Explanation:**

- The handler fires at `0x0800015c` which matches the map file address for
  `SysTick_Handler`.
- On the first hit `systick_count` is still 0 because the breakpoint halts before
  the increment instruction executes.
- After the second `continue`, the handler fires again and `systick_count` is 1
  — the first increment has committed to RAM.
- After the third `continue` it is 2, confirming the counter increments by exactly
  1 on each interrupt. The interrupt is working correctly.

---

# File Structure

```
stm32_qemu_baremetal_Aditya Jha/
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
<img width="1229" height="1280" alt="image" src="https://github.com/user-attachments/assets/bc067106-58a4-4f66-ad69-c5e7dbe93c84" />
<img width="1232" height="1280" alt="image" src="https://github.com/user-attachments/assets/4a98de40-060a-4494-8c95-73206849027e" />
<img width="1280" height="924" alt="image" src="https://github.com/user-attachments/assets/710a7de6-6caf-4eed-a63f-5f491d3f92bf" />
<img width="1209" height="1280" alt="image" src="https://github.com/user-attachments/assets/a0e6ea5d-954d-483c-b656-bf0d5b7be1b5" />
<img width="1280" height="883" alt="image" src="https://github.com/user-attachments/assets/bc7388ac-d748-4221-8cf2-1ac797c68b63" />




# Conclusion

This assignment demonstrates the full bare-metal boot sequence of a Cortex-M4
processor. The vector table, Reset_Handler, memory initialization, linker script,
semihosting output, and SysTick interrupt were all implemented from scratch without
any vendor library. GDB evidence confirms that every stage of the boot sequence —
SP initialization, PC jump to Reset_Handler, .data copy, .bss zeroing, and SysTick
interrupt delivery — works as expected.
