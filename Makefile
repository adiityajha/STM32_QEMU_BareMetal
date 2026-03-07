CC      = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
SIZE    = arm-none-eabi-size

TARGET    = firmware
C_SRCS    = src/main.c
S_SRCS    = startup/startup_stm32f4.s
LD_SCRIPT = ld/linker.ld

OBJS = $(C_SRCS:.c=.o) $(S_SRCS:.s=.o)

CFLAGS  = -mcpu=cortex-m4 -mthumb -O0 -g -Wall -ffreestanding -nostdlib -mfpu=fpv4-sp-d16 -mfloat-abi=hard
ASFLAGS = $(CFLAGS)
LDFLAGS = -T $(LD_SCRIPT) -nostdlib -Wl,-Map=$(TARGET).map

.PHONY: all clean qemu qemu-gdb gdb

all: $(TARGET).bin

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.s
	$(CC) $(ASFLAGS) -c $< -o $@

$(TARGET).elf: $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $@
	$(SIZE) $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

qemu: $(TARGET).bin
	qemu-system-arm -M olimex-stm32-h405 -kernel $(TARGET).bin -semihosting-config enable=on,target=native -nographic

qemu-gdb: $(TARGET).bin
	qemu-system-arm -M olimex-stm32-h405 -kernel $(TARGET).bin -semihosting-config enable=on,target=native -S -gdb tcp::3333 -nographic

gdb: $(TARGET).elf
	arm-none-eabi-gdb $(TARGET).elf -ex "target remote :3333" -ex "monitor reset halt" -ex "load" -ex "break main" -ex "continue"

clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).bin $(TARGET).map
