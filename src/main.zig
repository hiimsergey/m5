// TODO
// variables are not "0" by default but undefined
// expression containing these variables are automatically false
// keyword: assert <expr> if expr is false, results in error
// arguments: lt {-p:prefix {(-d:key(=val)) {input}}+ -o output }
// support -- as output that lets you use the file "-" as output
// ^ means, ExpectationStatus.output gets delayed
// the output-first notation allows having nothing as prefix
// \; is probably the termination character
//
// lt out.1 
//

// TODO inputcontext
// fd
// prefix
// macros
// output fd

const std = @import("std");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("AllocatorWrapper.zig");

const Context = struct {
	needs_help: bool = true,
	error_occured: bool = false,
	prefix: []const u8 = "",
	macros: std.StringHashMap([]const u8),

	fn init(gpa: Allocator) Context {
		return .{
			.macros = std.StringHashMap([]const u8).init(gpa)
		};
	}

	fn deinit(self: *Context) void {
		self.macros.deinit();
	}
};

const system_error_code = 71;
const help_text =
	\\lt - a simple text file processor
	\\by Sergey Lavrent (https://github.com/hiimsergey/lt)
	\\v0.1.1   GPL-3.0 license
	\\
	\\TODO
	\\
;

pub fn main() u8 {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();
	const gpa = aw.allocator(std.heap.smp_allocator);

	var args = std.process.argsWithAllocator(gpa) catch return system_error_code;
	defer args.deinit();

	_ = args.skip();

	var ctx = Context.init(gpa);
	defer ctx.deinit();

	batches: while (true) {
		const output_path = output: {
			const arg = args.next() orelse break :batches;
			// TODO NOW PLAN
			// -- -> next arg must be output
			// --help -> help msg
			// -flag -> error: no output
			// else -> needshelp is false; fetch fd
			ctx.needs_help = false;
			break :output arg;
		};
		_ = output_path;
		// TODO HERE fetch output fd

		while (args.next()) |arg| {
			_ = arg;
			// TODO PLAN arg
			// \; -> processBatch; continue :batches
		} else {
			// TODO HERE processBatch
			break :batches;
		}
	}

	if (ctx.needs_help) {
		// TODO better logging system
		std.debug.print(help_text, .{});
		return 1;
	}
	return @intFromBool(ctx.error_occured);
}
