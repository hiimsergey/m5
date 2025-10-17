const std = @import("std");
const a = @import("alias.zig");
const arguments = @import("arguments.zig");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("allocator.zig").AllocatorWrapper;
const M5Error = @import("error.zig").M5Error;
const Preprocessor = @import("Preprocessor.zig");

pub fn main() u8 {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();

	const allocator = aw.allocator();

	const args = std.process.argsAlloc(allocator) catch return 1;
	defer std.process.argsFree(allocator, args);

	arguments.validate(args) catch return 1;

	var pp = Preprocessor.init(allocator) catch return 1;
	defer pp.deinit(allocator);

	pp.run(allocator, args) catch return 1;

	return 0;
}

// TODO FINAL COMMENT ALL
// TODO "m5 -p foo bar.zig" just returns 0
