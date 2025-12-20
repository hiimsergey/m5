const std = @import("std");
const a = @import("alias.zig");
const arguments = @import("arguments.zig");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("allocator.zig").AllocatorWrapper;
const Preprocessor = @import("Preprocessor.zig");

pub fn main() u8 {
	real_main() catch return 1;
	return 0;
}

fn real_main() !void {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();
	const allocator = aw.allocator();

	defer a.flush_stdout();
	errdefer a.flush_stderr();

	const args = try std.process.argsAlloc(allocator);
	defer std.process.argsFree(allocator, args);

	try arguments.validate(args);

	var pp = try Preprocessor.init(allocator);
	defer pp.deinit(allocator);

	try pp.run(allocator, args);
}

// TODO NOW remove all instances of allocating. ts is redundant
// TODO FINAL COMMENT ALL
// TODO FINAL CONSIDER replacing usize with u32 everywhere
// TODO FINAL ADD input from piping
// TODO FINAL REMOVE std.debug.print calls

// TODO TEST PLAN
// nested ifs
// no end
// too much end
// ! operator
// (a > b) == 1
// if-elif-end
// -o foo -o bar
// syntax error (with linenr)
// zig-out/bin/m5 -p m5 .zig-cache/tmp/fVS2W6qQrVVELE26/test.txt silently fails
