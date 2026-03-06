const std = @import("std");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Map = @import("root").Map;
const Self = @This();

flags: packed struct(u8) {
	// TODO FINAL CHECK implemented
	verbose: bool = false,
	// TODO FINAL CHECK implemented
	safe: bool = false,
	_: u6 = 0
} = .{},
output: ?File = null,
input: ?File = null,
prefix: ?[]const u8 = null,
_prefix_buf: [64]u8 = undefined,
macros: Map,

pub fn init(gpa: Allocator) Self {
	return .{ .macros = Map.init(gpa) };
}

pub fn deinit(self: *Self) void {
	if (self.output) |file| file.close();
	if (self.input) |file| file.close();
	self.macros.deinit();
}

pub fn run(self: *const Self) error{Generic}!void {
	_ = self;
}
