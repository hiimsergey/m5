const std = @import("std");
const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("allocator.zig").AllocatorWrapper;
const StringList = std.ArrayList([]const u8);
const StringSet = std.StringHashMap(void);

const Context = struct {
	const Self = @This();

	inputs: StringList,
	macros: StringSet,
	output: ?[]const u8,
	prefix: []const u8,
	verbose: bool,

	pub fn init(allocator: Allocator) Self {
		return .{
			.inputs = StringList.init(allocator),
			.macros = StringSet.init(allocator),
			.output = null,
			.prefix = "",
			.verbose = false
		};
	}

	pub fn clear(self: *Self) void {
		self.inputs.shrinkRetainingCapacity(0);
		self.macros.clearRetainingCapacity();
		self.output = null;
	}

	pub fn deinit(self: *Self) void {
		self.inputs.deinit();
		self.macros.deinit();
	}
};

const flags = struct {
	const BOOLEAN  = [_][]const u8{ "--verbose", "-v" };
	const GLUED    = [_][]const u8{ "-D", "-U" };

	const DEFINE   = [_][]const u8{ "--define", "-D" };
	const UNDEFINE = [_][]const u8{ "--undefine", "-U" };
	const PREFIX   = [_][]const u8{ "--prefix", "-p" };
	const OUTPUT   = [_][]const u8{ "--output", "-o" };

	pub inline fn is_glued(flag: []const u8) bool {
		inline for (GLUED) |garg|
			if (std.mem.startsWith(u8, flag, garg)) return true;
		return false;
	}
};

const preprocessor = struct {
	pub fn validate_args(args: [][:0]u8) !void {
		var prefix_encountered = false;

		for (args[1..], 1..) |arg, i| {
			const is_prefix: bool = contains(&flags.PREFIX, arg);
			if (prefix_encountered and is_prefix) return error.BadArgs;
			prefix_encountered = is_prefix;

			if (contains(&flags.OUTPUT, arg)) {
				var ii: usize = i;
				while (contains(&flags.BOOLEAN, args[ii])) : (ii += 1) {}
				if (contains(&flags.DEFINE, args[ii])) return error.BadArgs;
			} else if (contains(&flags.DEFINE ++ flags.UNDEFINE ++ flags.PREFIX, arg)) {
				if (args.len <= i or args[i + 1][0] == '-') return error.BadArgs;
			} else if (contains(&flags.GLUED, arg)) {
				if (arg[2] == '-') return error.BadArgs;
			} else if (arg[0] == '-') return error.BadArgs;
			// ^ TODO DEBUG why is "m5 --prefix something" invalid?
		}
	}

	pub fn run(allocator: Allocator, ctx: *Context, args: [][:0]u8) !void {
		_ = allocator;

		for (args[1..], 1..) |arg, i| {
			ctx.clear();

			if (contains(&flags.DEFINE, arg)) {
				try ctx.macros.put(args[i + 1], {});
			} else if (startswith(arg, "-D")) {
				try ctx.macros.put(arg[2..], {});
			} if (contains(&flags.UNDEFINE, arg)) {
				_ = ctx.macros.remove(args[i + 1]);
			} else if (startswith(arg, "-U")) {
				_ = ctx.macros.remove(arg[2..]);
			}

			// TODO NOW PLAN
			// complete this if-else chain with all the other flags
			// start preprocessing pair
		}
	}
};

inline fn contains(haystack: []const []const u8, needle: []const u8) bool {
	return std.mem.containsAtLeast(u8, @ptrCast(haystack), 1, needle);
}
inline fn eql(a: []const u8, b: []const u8) bool {
	return std.mem.eql(u8, a, b);
}
inline fn startswith(a: []const u8, b: []const u8) bool {
	return std.mem.startsWith(u8, a, b);
}

pub fn main() !void {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();

	const allocator = aw.allocator();

	var ctx = Context.init(allocator);
	defer ctx.deinit();

	const args = try std.process.argsAlloc(allocator);
	defer std.process.argsFree(allocator, args);

	try preprocessor.validate_args(args);
	try preprocessor.run(allocator, &ctx, args);

	// TODO NOTE
	// implement PEMDAS
}
