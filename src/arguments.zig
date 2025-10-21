const std = @import("std");
const a = @import("alias.zig");

pub const FlagState = enum(u8) {
	not_encountered,
	expecting_arg,
	arg_encountered
};
const M5Error = @import("error.zig").M5Error;

pub fn validate(args: [][:0]u8) !void {
	if (args.len < 2 or a.contains_str(args, "--help") or a.contains_str(args, "-h")) {
		a.print_help();
		a.flush();
		return error.Help;
	}

	var inputs_encountered = false;

	var o_state = FlagState.not_encountered;
	var p_state = FlagState.not_encountered;

	for (args[1..], 1..) |arg, i| {
		if (a.eql(arg, "-o")) {
			if (!inputs_encountered) {
				a.errln(
					\\Invalid args! -o flag has no preceeding inputs!
					\\See 'm5 -h' for correct usage.
					, .{}
				);
				return M5Error.BadArgs;
			}
			if (i == args.len - 1) {
				a.errln(
					\\Invalid args! No output after -o flag.
					\\See 'm5 -h' for correct usage.
					, .{}
				);
				return M5Error.BadArgs;
			}
			if (args[i + 1][0] == '-') {
				a.errln(
					\\Invalid args! -o flag can't be followed by another flag.
					\\See 'm5 -h' for correct usage.
					, .{}
				);
				return M5Error.BadArgs;
			}
			o_state = .expecting_arg;
		}
		else if (a.eql(arg, "-p")) {
			if (p_state != .not_encountered) {
				a.errln(
					\\Invalid args! Trying to pass a second -p flag.
					\\See 'm5 -h' for correct usage.
					, .{}
				);
				return M5Error.BadArgs;
			}
			if (i == args.len - 1) {
				a.errln(
					\\Invalid args! No prefix after -p flag.
					\\See 'm5 -h' for correct usage.
					, .{}
				);
				return M5Error.BadArgs;
			}
			if (args[i + 1][0] == '-') {
				a.errln(
					\\Invalid args! -p flag can't be followed by another flag.
					\\See 'm5 -h' for correct usage.
					, .{}
				);
				return M5Error.BadArgs;
			}
			p_state = .expecting_arg;
		}
		else if (a.startswith(arg, "-D")) {
			if (arg.len == "-D".len) {
				a.errln(
					\\Invalid args! -D flag must follow a macro name with an optional value.
					\\See 'm5 -h' for correct usage.
					, .{}
				);
				return M5Error.BadArgs;
			}
		}
		else if (a.eql(arg, "-v")) continue
		else if (arg[0] == '-') {
			a.errln(
				\\Invalid args! Non-existent flag given, i.e. one that's none out of thse:
				\\  -D, -h, -o, -p, -v
				\\See 'm5 -h' for correct usage.
				, .{}
			);
			return M5Error.BadArgs;
		}
		else {
			if (o_state == .expecting_arg) {
				o_state = .arg_encountered;
				continue;
			}
			if (p_state == .expecting_arg) {
				p_state = .arg_encountered;
				continue;
			}

			_ = std.fs.cwd().statFile(arg) catch {
				a.errln("Could not open input file '{s}'!", .{arg});
				return M5Error.BadArgs;
			};
			inputs_encountered = true;
		}
	}
}
