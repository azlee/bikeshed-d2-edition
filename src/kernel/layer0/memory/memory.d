module kernel.layer0.memory.memory;

import kernel.layer0.serial;
import kernel.layer0.memory.malloc;
import kernel.layer0.memory.emplace;
import kernel.layer0.memory.mmap_list;

import physAllocator = kernel.layer0.memory.iPhysicalAllocator;
import virtAllocator = kernel.layer0.memory.iVirtualAllocator;

__gshared:
nothrow:
// These are linker symbols,
// To get the address of the end of the kernel, take
// the address of KERNEL_END.
// Similarly to get the address of the start of the
// kernel take the address of KERNEL_START.
// TODO - virtual or physical addresses?
extern(C) int KERNEL_END;   // Assumed to be aligned to 4-byte boundary
extern(C) int KERNEL_START;

enum PAGE_SIZE = 4096;

// Gathers a bunch of information
// about the machines memory layout
// and size in one location
struct MemoryInfo
{
	uint memory_total;
	uint kernel_start;
	uint kernel_end;
	uint mmap_count;
	const(MemoryMap)* mmap;
}

// The global memory information struct.
// Contains information about how much
// memory the current machine has available.
MemoryInfo g_memoryInfo = void;

align(1) /* Means pack the values */
struct SMAPEntry
{
	uint baseL;
	uint baseH;
	uint lengthL;
	uint lengthH;
	ushort type;
	uint ACPI;
}

void
detect_memory()
{
	assert(SMAPEntry.sizeof == 24);

	// The BIOS uses the 0xE820 call to get a pretty good
	// memory map of the system. It stores an array of and
	// count of the SMAP structs at the below addresses.
	enum SMAP_COUNT   = 0x2D00;
	enum SMAP_ADDRESS = 0x2D04;

	int count = *(cast(int *)SMAP_COUNT);
	if (count < 0)
	{
		serial_outln("Failed to get memory map");
		asm{hlt;}
	}

	// Need to go through and cleanup what's been given by
	// the BIOS. Sometimes the regions overlap or need to
	// be merged together.
	initialize_mmap_list();

	SMAPEntry* entry = cast(SMAPEntry*) SMAP_ADDRESS;
	for (int i = 0; i < count; ++i, ++entry)
	{
		if (entry.type == 0x1) // Available memory
		{
			const uint bh = entry.baseH;
			const uint bl = entry.baseL;
			const uint lh = entry.lengthH;
			const uint ll = entry.lengthL;

			uint start  = cast(uint) ((cast(ulong)bh << 32) | bl);
			uint length = cast(uint) ((cast(ulong)lh << 32) | ll);

			add_usable_region(start, length);
		}
	}

	// Reserve regions the kernel uses
	reserve_region(cast(uint) &KERNEL_START, 0x200000 - cast(uint)&KERNEL_START);
	reserve_region(0x500, 0x2500 + 256*4); // GDT + IDT
	reserve_region(0x7C00, 1536); // Bootloader
	reserve_region(0x2D00, SMAPEntry.sizeof*count); // SMAP entries

	// Loop through all the entries
	g_memoryInfo.mmap_count = get_mmap_count();
	g_memoryInfo.mmap = get_mmap_start();
	g_memoryInfo.kernel_start = cast(uint) &KERNEL_START;
	// The memory map starts at the current end of the kernel
	g_memoryInfo.kernel_end = cast(uint) (get_mmap_start() + get_mmap_count());

	// Loop through and find the total amount of memory
	const(MemoryMap)* mm = g_memoryInfo.mmap;
	g_memoryInfo.memory_total = 0;
	for (int i = 0; i < g_memoryInfo.mmap_count; ++i, ++mm)
	{
		g_memoryInfo.memory_total += mm.length;	
	}

	// Print some debug info
	serial_outln("Memory information");
	serial_outln("Kernel start: ", g_memoryInfo.kernel_start);
	serial_outln("Kernel end:   ", g_memoryInfo.kernel_end, " (Orig: ", (cast(uint)&KERNEL_END), ")");
	serial_outln("Total memory: ", g_memoryInfo.memory_total);
	serial_outln("Mmap count:   ", g_memoryInfo.mmap_count);

	print_mmap_list();

	serial_outln("\nSMAP:");
	entry = cast(SMAPEntry*) SMAP_ADDRESS;
	for (int i = 0; i < count; ++i)
	{
		uint start = cast(uint)((cast(ulong)entry.baseH << 32) | entry.baseL);
		uint length = cast(uint)((cast(ulong)entry.lengthH << 32) | entry.lengthL);

		serial_outln("S: ", start, " L: ", length, " T: ", entry.type, " A: ", entry.ACPI);
		++entry;
	}

	asm { hlt; }
}

void
init_memory()
{
	serial_outln("\nMemory: Initializing");

	detect_memory();

	//============================================================================
	// Initialize the physical allocator
	//============================================================================
	physAllocator.initialize(g_memoryInfo);

	// Reserve addresses in the physical allocator so they're not
	// given out as addresses
	physAllocator.reserve_range(0x0, 0x200000);

	//============================================================================
	// End of physical allocator initialization
	//============================================================================

	//============================================================================
	// Initialize the virtual allocator
	//============================================================================

	virtAllocator.initialize(g_memoryInfo);

	//============================================================================
	// End of virtual allocator initialization
	//============================================================================

	// Setup the kernel's heap
	malloc_initialize();
}

