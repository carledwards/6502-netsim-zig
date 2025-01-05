const std = @import("std");
const CPU = @import("cpu.zig").CPU;
const Memory = @import("memory.zig").Memory;

// Global state for bus callbacks
var global_mb: ?*Motherboard = null;

pub const RamSize = 8 * 1024; // 8K
pub const RomSize = 8 * 1024; // 8K
pub const RamBaseAddr = 0x0000;
pub const RomBaseAddr = 0xE000;

pub const Motherboard = struct {
    allocator: std.mem.Allocator,
    cpu: *CPU,
    ram: *Memory,
    rom: *Memory,

    pub fn init(allocator: std.mem.Allocator, trans_defs_path: []const u8, seg_defs_path: []const u8) !*Motherboard {
        const self = try allocator.create(Motherboard);
        errdefer allocator.destroy(self);

        // Initialize RAM and ROM
        self.ram = try Memory.init(allocator, RamSize, false);
        errdefer self.ram.deinit();

        self.rom = try Memory.init(allocator, RomSize, true);
        errdefer self.rom.deinit();

        // Set global state for callbacks
        global_mb = self;

        // Initialize CPU with bus callbacks
        self.cpu = try CPU.init(
            allocator,
            struct {
                pub fn read(addr: usize) u8 {
                    const mb = global_mb.?;
                    if (addr < RamBaseAddr + RamSize) {
                        return mb.ram.read(addr);
                    } else if (addr >= RomBaseAddr) {
                        return mb.rom.read(addr - RomBaseAddr);
                    }
                    return 0x00;
                }
            }.read,
            struct {
                pub fn write(addr: usize, val: u8) void {
                    const mb = global_mb.?;
                    if (addr < RamBaseAddr + RamSize) {
                        mb.ram.write(addr, val);
                    }
                    // Writes to ROM are ignored
                }
            }.write,
        );
        errdefer self.cpu.deinit();

        // Load transistor and segment definitions
        try self.cpu.setupTransistors(trans_defs_path);
        try self.cpu.setupNodes(seg_defs_path);
        try self.cpu.connectTransistors();

        // Reset CPU
        try self.cpu.reset();

        return self;
    }

    pub fn deinit(self: *Motherboard) void {
        // First clear global state to prevent callbacks from accessing freed memory
        global_mb = null;

        // Now clean up components
        self.cpu.deinit();
        self.ram.deinit();
        self.rom.deinit();
    }

    pub fn clockTick(self: *Motherboard) void {
        self.cpu.halfStep();
    }

    pub fn getROM(self: *Motherboard) *Memory {
        return self.rom;
    }

    pub fn getRAM(self: *Motherboard) *Memory {
        return self.ram;
    }
};
