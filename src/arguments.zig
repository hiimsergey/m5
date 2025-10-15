const a = @import("alias.zig");

const M5Error = @import("error.zig").M5Error;

pub fn validate(args: [][:0]u8) !void {
	if (args.len < 2 or a.contains_str(args, "--help") or a.contains_str(args, "-h")) {
		a.print_help();
		a.flush();
		return error.Help;
	}

	var inputs_encountered = false;
	var prefix_encountered = false;

	for (args[1..], 1..) |arg, i| {
		if (a.eql(arg, "-p")) {
			if (prefix_encountered) {
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
			prefix_encountered = true;
		}
		else if (a.eql(arg, "-o")) {
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
		else inputs_encountered = true;
	}
}
