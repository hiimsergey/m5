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

// TODO NOW i think if-elif-end doesnt work at all rn
// TODO FINAL COMMENT ALL
// TODO "m5 -p m5 /tmp/alice -D ALICE -D BOB" just silently quits

// TODO TEST PLAN
// no end
// too much end
// ! operator
// (a > b) == 1
// if-elif-end
// nested ifs
// -o foo -o bar
