const builtin = @import("builtin");
const std = @import("std");

/// Comptime wrapper that resolves to the slow but helpful `DebugAllocator` in
/// Debug mode and the performant but dangerous `c_allocator` in all the other modes.
pub const AllocatorWrapper = if (builtin.mode == .Debug) struct {
	const Self = @This();
	const DebugAllocator = std.heap.DebugAllocator(.{});

	dbg_state: DebugAllocator,

	/// Initializes Zig's `DebugAllocator`.
	pub fn init() Self {
		return .{ .dbg_state = DebugAllocator.init };
	}

	/// Returns the `DebugAllocator`'s allocator.
	pub fn allocator(self: *Self) std.mem.Allocator {
		return self.dbg_state.allocator();
	}

	/// Deinits Zig's `DebugAllocator` and log an error message if
	/// the program contains Zig-side memory leaks.
	pub fn deinit(self: *Self) void {
		if (self.dbg_state.deinit() == .leak)
			std.debug.print("ERROR: Leaks found!", .{});
	}
} else struct {
	const Self = @This();

	/// Trivial struct initialization.
	pub fn init() Self { return .{}; }

	/// Simply returns `@import("std").heap.c_allocator`.
	pub fn allocator(_: *Self) std.mem.Allocator {
		return std.heap.c_allocator;
	}

	/// NOP function.
	pub fn deinit(_: *Self) void {}
};
