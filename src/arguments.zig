// TODO RENAME file to validate.zig
const std = @import("std");
const log = @import("log.zig");

const stderr = log.stderr;

const E = error.Generic;

pub const FlagState = enum(u8) {
	not_encountered,
	expecting_arg,
	arg_encountered
};

const invalid_args_text = "Invalid args! ";
const correct_usage_text = "See 'm5 -h' for correct usage.\n";

/// Check command line arguments for validity. That includes the correct argument syntax
/// and the existence of the input files.
pub fn validate(args: [][:0]u8) !void {
	if (args.len == 1 or containsString(args, "--help") or containsString(args, "-h")) {
		stderr.print(log.help_text, .{}) catch {};
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

		if (eql(arg, "-o")) {
			if (!inputs_encountered) {
				inline for (.{
					log.error_tag,
					invalid_args_text,
					"-o flag has no preceeding inputs!\n",
					correct_usage_text,
					log.style_reset
				}) |str| stderr.print(str, .{}) catch {};
				return E;
			}
			if (i == args.len - 1) {
				inline for (.{
					log.error_tag,
					invalid_args_text,
					"No output after -o flag.\n",
					correct_usage_text,
					log.style_reset
				}) |str| stderr.print(str, .{}) catch {};
				return E;
			}
			o_state = .expecting_arg;
		}
		else if (eql(arg, "-p")) {
			if (i == args.len - 1) {
				inline for (.{
					log.error_tag,
					invalid_args_text,
					"No prefix after -p flag.\n",
					correct_usage_text,
					log.style_reset
				}) |str| stderr.print(str, .{}) catch {};
				return E;
			}
			p_state = .expecting_arg;
		}
		else if (startsWith(arg, "-D")) {
			// TODO handle string defines like -Dfoo="bar baz"
			const definition = arg["-D".len..];
			if (definition.len == 0) {
				inline for (.{
					log.error_tag,
					invalid_args_text,
					"-D flag must follow a macro name with an optional value.\n",
					correct_usage_text,
					log.style_reset
				}) |str| stderr.print(str, .{}) catch {};
				return E;
			}
			switch (definition[0]) {
				'-', '0'...'9' => {
					inline for (.{
						log.error_tag,
						invalid_args_text,
						"You can't define a macro starting with a number!\n",
						correct_usage_text,
						log.style_reset
					}) |str| stderr.print(str, .{}) catch {};
					return E;
				},
				else => {}
			}
		}
		else if (eql(arg, "-v")) continue
		else if (arg[0] == '-') {
			inline for (.{
				log.error_tag,
				invalid_args_text,
				\\Non-existent flag given, i.e. one that's none out of these:
				\\  -D, -h, -o, -p, -v
				\\
				, correct_usage_text,
				log.style_reset
			}) |str| stderr.print(str, .{}) catch {};
			return E;
		}
		else {
			if (p_state != .arg_encountered) {
				stderr.print(log.error_tag, .{}) catch {};
				stderr.print(invalid_args_text, .{}) catch {};
				stderr.print(
					\\No prefix given for input '{s}'!
					\\You can pass a prefix with the -p flag!
					\\
				, .{args[i]}) catch {};
				stderr.print(correct_usage_text, .{}) catch {};
				stderr.print(log.style_reset, .{}) catch {};
				return E;
			}

			// TODO REMOVE
			// this is redundant since `validateInput`
			_ = std.fs.cwd().statFile(arg) catch {
				log.err("Could not open input file '{s}'!\n", .{arg});
				return E;
			};
			// TOOD NOW CONSIDER MOVE validate_input() here
			inputs_encountered = true;
		}
	}
}

pub fn startsWith(haystack: []const u8, needle: []const u8) bool {
	return std.mem.startsWith(u8, haystack, needle);
}

pub fn eql(a: []const u8, b: []const u8) bool {
	return std.mem.eql(u8, a, b);
}

/// Return whether `haystack` contains an element equal to `needle`.
pub fn containsString(haystack: []const []const u8, needle: []const u8) bool {
	for (haystack) |hay| if (eql(hay, needle)) return true;
	return false;
}
