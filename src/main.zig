const std = @import("std");
const arguments = @import("arguments.zig");
const log = @import("log.zig");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("AllocatorWrapper.zig");
const Processor = @import("Processor.zig");

pub fn main() u8 {
	realMain() catch return 1;
	return 0;
}

fn realMain() !void {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();
	const gpa = aw.allocator();

	defer log.stdout.flush() catch {};
	errdefer log.stderr.flush() catch {};

	const args = try std.process.argsAlloc(gpa);
	defer std.process.argsFree(gpa, args);

	// All arguments and input files are checked prior to catch errors
	// prematurely so that we only start processing when everything's right.
	try arguments.validate(args);

	var procr = try Processor.init(gpa);
	defer procr.deinit(gpa);

	try procr.run(gpa, args);
}

test {
	_ = @import("test.zig");
}

// TODO CHECK if m5 lines are also ignored in falsy branches
// TODO give tests proper structure
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

// TODO PLAN possible future release
// m5 label name:label         - define label
// m5 goto name:label          - jump to line n in input file 
// m5 after name:label         - sets default label to jump after every single non-directive line
//     (if no arg is given, handler is reset)
// m5 resume                   - return to where you jumped here from with after
// m5 back n:int               - delete n characters from output (allows inline generation)
// m5 define name:str val:expr - define variable
// m5 undef name:str           - delete variable
//     (since undefinition equals value 0, maybe this is redundant)
// m5 write content:expr       - writes the value of the expression to the output file
