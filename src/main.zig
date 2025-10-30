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

	defer a.flush();

	const args = std.process.argsAlloc(allocator) catch return 1;
	defer std.process.argsFree(allocator, args);

	arguments.validate(args) catch return 1;

	var pp = Preprocessor.init(allocator) catch return 1;
	defer pp.deinit(allocator);

	pp.run(allocator, args) catch return 1;
	return 0;
}

// TODO NOW IMPLEMENT nestes ifs
// TODO FINAL COMMENT ALL
// TODO FINAL ADD input from piping

// TODO TEST PLAN
// nested ifs
// no end
// too much end
// ! operator
// (a > b) == 1
// if-elif-end
// -o foo -o bar
// syntax error (with linenr)
