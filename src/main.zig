const std = @import("std");
const a = @import("alias.zig");
const arguments = @import("arguments.zig");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("allocator.zig").AllocatorWrapper;
const Processor = @import("Processor.zig");

pub fn main() u8 {
	real_main() catch return 1;
	return 0;
}

fn real_main() !void {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();
	const gpa = aw.allocator();

	defer a.stdout.interface.flush() catch {};
	errdefer a.stderr.interface.flush() catch {};

	const args = try std.process.argsAlloc(gpa);
	defer std.process.argsFree(gpa, args);

	try arguments.validate(args);

	var pp = try Processor.init(gpa);
	defer pp.deinit(gpa);

	try pp.run(gpa, args);
}

// TODO "m5 elseX" should complain that elseX is an invalid keyword
// TODO FINAL COMMENT ALL
// TODO FINAL CONSIDER replacing usize with u32 everywhere
// TODO FINAL CHECK if surpassing the scope limit is handled elegantly
// TODO FINAL REMOVE std.debug.print calls

// TODO ADD tests:
//     nested ifs
//     no end
//     too much end
//     ! operator
//     (a > b) == 1
//     if-elif-end
//     -o foo -o bar
//     syntax error (with linenr)
//     zig-out/bin/m5 -p m5 .zig-cache/tmp/fVS2W6qQrVVELE26/test.txt silently fails
