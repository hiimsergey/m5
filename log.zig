const std = @import("std");

const Io = std.Io;
const OpenError = Io.File.OpenError;

const error_tag = "error: ";

pub var stderr: *Io.Writer = undefined;
var stderr_buf: [256]u8 = undefined;
var stderr_wrapper: Io.File.Writer = undefined;

pub fn setup(io: Io) void {
	stderr_wrapper = Io.File.stderr().writer(io, &stderr_buf);
	stderr = &stderr_wrapper.interface;
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
	stderr.print("\x1b[31;1m" ++ error_tag ++ "\x1b[0m", .{}) catch {};

	const fmt_indented: []const u8 = comptime fmt_indented: {
		var it = std.mem.tokenizeScalar(u8, fmt, '\n');
		const spaces: [error_tag.len]u8 = @splat(' ');

		var result = it.next().?;
		while (it.next()) |line| result = result ++ "\n" ++ spaces ++ line;
		result = result ++ "\n";
		break :fmt_indented result;
	};

	stderr.print(fmt_indented, args) catch {};
}

pub fn errWithHelp(comptime fmt: []const u8, args: anytype) void {
	err(fmt ++ "\nSee `m5 --help` for correct usage!", args);
}

pub fn errWithLineNr(linenr: usize, comptime fmt: []const u8, args: anytype) void {
	err("line {d}: " ++ fmt, .{linenr} ++ args);
}

/// Logs on failed file opening.
pub fn openError(e: OpenError, arg: []const u8) void {
	switch (e) {
		OpenError.FileNotFound => err("Input '{s}' does not exist!", .{arg}),
		OpenError.AccessDenied =>
			err("Permission to open input '{s}' denied!", .{arg}),
		OpenError.IsDir => err("Input '{s}' is not a file but a directory!", .{arg}),
		else => err("Failed to open input '{s}'!", .{arg})
	}
}
