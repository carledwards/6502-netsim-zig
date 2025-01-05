const std = @import("std");

pub const Memory = struct {
    allocator: std.mem.Allocator,
    size: usize,
    is_read_only: bool,
    memory: []u8,

    pub fn init(allocator: std.mem.Allocator, size: usize, is_read_only: bool) !*Memory {
        const self = try allocator.create(Memory);
        self.* = .{
            .allocator = allocator,
            .size = size,
            .is_read_only = is_read_only,
            .memory = try allocator.alloc(u8, size),
        };
        // Initialize memory to 0
        @memset(self.memory, 0);
        return self;
    }

    pub fn deinit(self: *Memory) void {
        self.allocator.free(self.memory);
        self.allocator.destroy(self);
    }

    pub fn write(self: *Memory, address: usize, data: u8) void {
        if (!self.is_read_only) {
            self.memory[address] = data;
        }
    }

    pub fn read(self: *Memory, address: usize) u8 {
        return self.memory[address];
    }

    pub fn reset(self: *Memory) void {
        if (!self.is_read_only) {
            @memset(self.memory, 0);
        }
    }
};
