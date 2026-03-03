/// Comptime wrapper that resolves to the slow but helpful `DebugAllocator` in
/// Debug mode and user-chosen one in all the other modes.
const Self = @This();

const builtin = @import("builtin");
const std = @import("std");
const log = std.log;

const Allocator = std.mem.Allocator;
const DebugAllocator = std.heap.DebugAllocator(.{});

dbg_state: if (is_debug) DebugAllocator else void,

const is_debug = builtin.mode == .Debug;

/// Initialize Zig's `DebugAllocator`.
pub fn init() Self {
	return if (is_debug) .{ .dbg_state = DebugAllocator.init } else .{ .dbg_state = {} };
}

/// Return the `DebugAllocator`'s allocator.
pub fn allocator(self: *Self, comptime release_mode_gpa: Allocator) Allocator {
	return if (is_debug) self.dbg_state.allocator() else release_mode_gpa;
}

/// Deinit Zig's `DebugAllocator`, if compiling in Debug mode.
/// Otherwise, this is a no-op.
pub fn deinit(self: *Self) void {
	if (is_debug) _ = self.dbg_state.deinit();
}
