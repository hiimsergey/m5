const std = @import("std");

const Io = std.Io;

const error_tag = "error: ";

pub var stderr: *Io.Writer = undefined;
var stderr_buf: [256]u8 = undefined;
var stderr_wrapper: Io.File.Writer = undefined;

pub fn setup(io: Io) void {
	stderr_wrapper = Io.File.stderr().writer(io, &stderr_buf);
	stderr = &stderr_wrapper.interface;
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
	stderr.print("\x1b[31;1m" ++ error_tag ++ "\x1b[0m", .{}) catch |e| {
		// TODO
		std.debug.print("TODO hello", .{});
		std.debug.print("{s}\n", .{@errorName(e)});
	};

	const fmt_indented: []const u8 = comptime fmt_indented: {
		var it = std.mem.tokenizeScalar(u8, fmt, '\n');
		const spaces: [error_tag.len]u8 = @splat(' ');

		var result = it.next().?;
		while (it.next()) |line| result = result ++ "\n" ++ spaces ++ line;
		result = result ++ "\n";
		break :fmt_indented result;
	};

	stderr.print(fmt_indented, args) catch |e| {
		// TODO
		std.debug.print("{s}\n", .{@errorName(e)});
	};
}

pub fn errWithHelp(comptime fmt: []const u8, args: anytype) void {
	err(fmt ++ "\nSee `m5 --help` for correct usage!", args);
}

pub fn errWithLineNr(linenr: usize, comptime fmt: []const u8, args: anytype) void {
	err("line {d}: " ++ fmt, .{linenr} ++ args);
}
