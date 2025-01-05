const std = @import("std");
const Motherboard = @import("motherboard.zig").Motherboard;

// Test program
const app_code = [_]u8{
    0xA9, 0x50, // lda #$FF
    0x8D, 0x00, 0x10, // sta $1000
    0xCE, 0x00, 0x10, // dec $1000
    0x4C, 0x05, 0xE0, // jmp $E002
};

// Include all possible errors from std.fs.File.OpenError and our custom errors
const Error = error{
    FileNotFound,
    NodeNotFound,
    OutOfMemory,
    AccessDenied,
    SharingViolation,
    PathAlreadyExists,
    PipeBusy,
    NameTooLong,
    InvalidUtf8,
    InvalidWtf8,
    BadPathName,
    Unexpected,
    NetworkNotFound,
    AntivirusInterference,
    SymLinkLoop,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    NoDevice,
    SystemResources,
    FileTooBig,
    IsDir,
    NoSpaceLeft,
    NotDir,
    DeviceBusy,
    FileLocksNotSupported,
    FileBusy,
    WouldBlock,
    InputOutput,
    OperationAborted,
    BrokenPipe,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    NotOpenForReading,
    SocketNotConnected,
    StreamTooLong,
    Overflow,
    InvalidCharacter,
};

pub fn main() Error!void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get paths relative to current directory
    const trans_defs_path = "data/transdefs.txt";
    const seg_defs_path = "data/segdefs.txt";

    std.debug.print("Loading definition files:\n  trans: {s}\n  segs: {s}\n", .{ trans_defs_path, seg_defs_path });

    // Initialize motherboard
    var mb = Motherboard.init(allocator, trans_defs_path, seg_defs_path) catch |err| {
        std.debug.print("Failed to initialize motherboard: {}\n", .{err});
        return err;
    };
    defer {
        mb.deinit();
        allocator.destroy(mb);
    }

    // Initialize ROM with test program
    const rom = mb.getROM();
    for (app_code, 0..) |v, i| {
        rom.write(i, v);
    }

    // Set 6502 reset vectors for starting address of app: $E000
    rom.write(0x1FFC, 0x00);
    rom.write(0x1FFD, 0xE0);

    // Run CPU for a short time and measure performance
    const start = std.time.milliTimestamp();
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        mb.clockTick();
    }

    const elapsed = std.time.milliTimestamp() - start;
    std.debug.print("Elapsed time: {}ms\n", .{elapsed});
}
