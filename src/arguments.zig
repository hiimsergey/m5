const a = @import("alias.zig");

const M5Error = @import("error.zig").M5Error;

const BOOLEAN = [_][]const u8{ "-v" };
const GLUED = [_][]const u8{ "-D", "-U" };
const FLAGS = BOOLEAN ++ GLUED ++ .{ "-o", "-p" };

pub fn validate(args: [][:0]u8) M5Error!void {
	var prefix_encountered = false;

	for (args[1..], 1..) |arg, i| {
		if (a.eql(arg, "-p")) {
			// TODO FINAL abstract away the check of "is the next arg a flag?"
			if (prefix_encountered or args.len <= i + 1 or args[i + 1][0] == '-')
				return M5Error.BadArgs;
			prefix_encountered = true;
		} else if (a.eql(arg, "-o")) {
			if (i == 1 or
				args[i][0] == '-' or
				a.contains(&args.BOOLEAN, args[i + 1]) or
				a.contains(&args.GLUED, arg[i + 1])) return M5Error.BadArgs;
		} else if (a.contains(&args.FLAGS, arg)) {
			if (args.len <= i + 1 or args[i + 1][0] == '-') return M5Error.BadArgs;
		} else if (a.contains(&args.GLUED, arg)) {
			const glued_arg_len = args.GLUED[0].len;
			if (arg.len <= glued_arg_len or arg[glued_arg_len] == '-')
				return M5Error.BadArgs;
		} else if (arg[0] == '-') return M5Error.BadArgs;
		// ^ TODO DEBUG why is "m5 --prefix something" invalid?
	}
}
