const std = @import("std");
const a = @import("alias.zig");
const arguments = @import("arguments.zig");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("allocator.zig").AllocatorWrapper;
const M5Error = @import("error.zig").M5Error;
const Preprocessor = @import("preprocessor.zig").Preprocessor;

pub fn main() M5Error!void {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();

	const allocator = aw.allocator();

	var pp = Preprocessor.init(allocator);
	defer pp.deinit();

	const args = try std.process.argsAlloc(allocator);
	defer std.process.argsFree(allocator, args);

	try arguments.validate(args);
	try Preprocessor.run(args);
}
