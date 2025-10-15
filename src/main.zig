const std = @import("std");
const a = @import("alias.zig");
const arguments = @import("arguments.zig");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("allocator.zig").AllocatorWrapper;
const M5Error = @import("error.zig").M5Error;
const Preprocessor = @import("Preprocessor.zig");

pub fn main() !u8 {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();

	const allocator = aw.allocator();

	const args = try std.process.argsAlloc(allocator);
	defer std.process.argsFree(allocator, args);

	// TODO FINAL CHECK how the program behaves when we put -h in the middle
	if (args.len < 2 or a.eql(args[1], "--help") or a.eql(args[1], "-h")) {
		a.print_help();
		a.flush();
		return 1;
	}

	var pp = try Preprocessor.init(allocator);
	defer pp.deinit(allocator);

	try arguments.validate(args);
	try pp.run(allocator, args);

	return 0;
}
