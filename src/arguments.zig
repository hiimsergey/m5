const std = @import("std");
const a = @import("alias.zig");

const E = error.Generic;

pub const FlagState = enum(u8) {
	not_encountered,
	expecting_arg,
	arg_encountered
};

const TEXT_INVALID_ARGS = "Invalid args! ";
const TEXT_CORRECT_USAGE = "See 'm5 -h' for correct usage.";

/// Check command line arguments for validity. That includes the correct argument syntax
/// and the existence of the input files.
pub fn validate(args: [][:0]u8) !void {
	if (args.len == 1 or a.contains_str(args, "--help") or a.contains_str(args, "-h")) {
		a.print_help();
		return E;
	}

	var inputs_encountered = false;
	var o_state = FlagState.not_encountered;
	var p_state = FlagState.not_encountered;

	for (args[1..], 1..) |arg, i| {
		if (o_state == .expecting_arg) {
			inputs_encountered = false;
			o_state = .arg_encountered;
			continue;
		}
		if (p_state == .expecting_arg) {
			p_state = .arg_encountered;
			continue;
		}

		if (a.eql(arg, "-o")) {
			if (!inputs_encountered) {
				a.errtag();
				a.err(TEXT_INVALID_ARGS, .{});
				a.errln("-o flag has no preceeding inputs!", .{});
				a.errln(TEXT_CORRECT_USAGE, .{});
				return E;
			}
			if (i == args.len - 1) {
				a.errtag();
				a.err(TEXT_INVALID_ARGS, .{});
				a.errln("No output after -o flag.", .{});
				a.errln(TEXT_CORRECT_USAGE, .{});
				return E;
			}
			o_state = .expecting_arg;
		}
		else if (a.eql(arg, "-p")) {
			if (p_state != .not_encountered) {
				a.errtag();
				a.err(TEXT_INVALID_ARGS, .{});
				a.errln("Trying to pass a second -p flag.", .{});
				a.errln(TEXT_CORRECT_USAGE, .{});
				return E;
			}
			if (i == args.len - 1) {
				a.errtag();
				a.err(TEXT_INVALID_ARGS, .{});
				a.errln("No prefix after -p flag.", .{});
				a.errln(TEXT_CORRECT_USAGE, .{});
				return E;
			}
			p_state = .expecting_arg;
		}
		else if (a.startswith(arg, "-D")) {
			const definition = arg["-D".len..];
			if (definition.len == 0) {
				a.errtag();
				a.err(TEXT_INVALID_ARGS, .{});
				a.errln("-D flag must follow a macro name with an optional value.", .{});
				a.errln(TEXT_CORRECT_USAGE, .{});
				return E;
			}
			switch (definition[0]) {
				'-', '0'...'9' => {
					a.errtag();
					a.err(TEXT_INVALID_ARGS, .{});
					a.errln("You can't define a macro starting with a dash or a number!", .{});
					a.errln(TEXT_CORRECT_USAGE, .{});
					return E;
				},
				else => {}
			}
		}
		else if (a.eql(arg, "-v")) continue
		else if (arg[0] == '-') {
			a.errtag();
			a.err(TEXT_INVALID_ARGS, .{});
			a.errln(
				\\Non-existent flag given, i.e. one that's none out of these:
				\\  -D, -h, -o, -p, -v
				, .{}
			);
			a.errln(TEXT_CORRECT_USAGE, .{});
			return E;
		}
		else {
			_ = std.fs.cwd().statFile(arg) catch {
				a.errtag();
				a.errln("Could not open input file '{s}'!", .{arg});
				return E;
			};
			// TOOD NOW CONSIDER MOVE validate_input() here
			inputs_encountered = true;
		}
	}
}
