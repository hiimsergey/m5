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

const Context = struct {
	verbose: bool = false,
	needs_help: bool = false,
	arg_i: usize = 0, // TODO DEPRECATE

	output: []const u8,
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

const help_text =
	\\lt - a simple text file processor
	\\by Sergey Lavrent (https://github.com/hiimsergey/lt)
	\\v0.1.1   GPL-3.0 license
	\\
	\\Usage:
	\\    lt (INPUTS | OPTION)...
	\\
;

pub fn main() u8 {
	// TODO better allocator
	const gpa = std.heap.smp_allocator;

	const args = std.process.argsAlloc(gpa) catch return 71;
	defer std.process.argsFree(gpa, args);

	if (args.len == 1 or containsString(args, "--help")) {
		// TODO use proper logging
		std.debug.print(help_text, .{});
		return 1;
	}

	// args[1..] skips executable name
	return run(args[1..]);
}

fn run(gpa: Allocator, args: [][:0]const u8) u8 {
	var ctx = Context.init(gpa);
	defer ctx.deinit();

	if (containsString(args, "-v")) ctx.verbose = true;

	batches: while (true) {
		if (ctx.arg_i == args.len) break :batches;

		// TODO NOW take iter based approach after all

		ctx.output = args[ctx.arg_i];
		if (ctx.output[0] == '-') {
			// TODO PLAN
			// -- -> next arg must be output
			// -flag -> error: no output
			// else -> fetch fd
		}

		while (true) {
			ctx.arg_i += 1;

		}
	}

	if (ctx.needs_help) {
		std.debug.print(help_text, .{});
		return 1;
	}

	return 8;
}

/// Returns true only if at least one element of `haystack` is equal to
/// `needle`, according to std.mem.eql.
fn containsString(haystack: []const []const u8, needle: []const u8) bool {
	// TODO CONSIDER simd
	for (haystack) |hay| if (std.mem.eql(u8, hay, needle)) return true;
	return false;
}
