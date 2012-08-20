CC=gcc
C_FLAG=-Wall -Werror -Wextra -pedantic -std=gnu99

DC=src/dlibrary/dmd/src/dmd
D_FLAGS=-m32 -Isrc -release -nofloat -w -wi -vtls

SOURCES=src/kernel/kmain.d src/kernel/vga.d

AS=as
AS_FLAGS=--32 -n32

LD=ld
LD_FLAGS=-m elf_i386 --oformat binary

OUTPUT_DIR=output
OBJ_DIR=obj

all: kernel

clean:
	/bin/rm -f $(OBJ_DIR)/*
	/bin/rm -f $(OUTPUT_DIR)/*

bootloader:
	$(AS) $(AS_FLAGS) src/boot/bootloader.S -o $(OBJ_DIR)/bootloader.o
	$(LD) $(LD_FLAGS) $(OBJ_DIR)/bootloader.o -Tsrc/boot/bootloader.ld -o $(OUTPUT_DIR)/bootloader.b

fancycat:
	$(CC) $(C_FLAGS) src/boot/FancyCat.c -o $(OUTPUT_DIR)/FancyCat

clib:
	$(DC) $(D_FLAGS) -c src/bikeshed-lib/stdlib.d -of$(OBJ_DIR)/stdlib.o 

kernel: clean bootloader fancycat clib
	$(AS) $(AS_FLAGS) src/kernel/constructors.S -o $(OBJ_DIR)/constructors.o		
	$(DC) $(D_FLAGS) -c src/kernel/kmain.d -Isrc -of$(OBJ_DIR)/kmain.o
	$(DC) $(D_FLAGS) -c src/kernel/vga.d -of$(OBJ_DIR)/vga.o
	$(DC) $(D_FLAGS) -c src/kernel/paging/memory.d -of$(OBJ_DIR)/memory.o
	$(LD) $(LD_FLAGS) -Tsrc/linker_scripts/kernel.ld $(OBJ_DIR)/constructors.o $(OBJ_DIR)/kmain.o src/bikeshed-lib/libdruntime-bikeshed32.a src/bikeshed-lib/libphobos2.a $(OBJ_DIR)/stdlib.o $(OBJ_DIR)/vga.o $(OBJ_DIR)/memory.o -o $(OUTPUT_DIR)/kernel.b
	$(LD) -m elf_i386 -Tsrc/linker_scripts/kernel.ld $(OBJ_DIR)/constructors.o $(OBJ_DIR)/kmain.o src/bikeshed-lib/libdruntime-bikeshed32.a src/bikeshed-lib/libphobos2.a $(OBJ_DIR)/stdlib.o $(OBJ_DIR)/vga.o $(OBJ_DIR)/memory.o -o $(OUTPUT_DIR)/kernel.o
	$(OUTPUT_DIR)/FancyCat 0x100000 $(OUTPUT_DIR)/kernel.b
	mv image.dat $(OUTPUT_DIR)/.
	cat $(OUTPUT_DIR)/bootloader.b $(OUTPUT_DIR)/image.dat > $(OUTPUT_DIR)/kernel.bin

qemu: kernel
	qemu-system-i386 -m 1024 -cpu core2duo -drive file=$(OUTPUT_DIR)/kernel.bin,format=raw,cyls=200,heads=16,secs=63 -monitor stdio -net user -net nic,model=i82559er -vga vmware
