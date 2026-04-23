const std = @import("std");

const error_tag = "\x1b[31;1merror:\x1b[0m ";

var stderr_buf: [128]u8 = undefined;
var stderr_wrapper = std.fs.File.stderr().writer(&stderr_buf);

pub const stderr = &stderr_wrapper.interface;

pub fn err(comptime fmt: []const u8, args: anytype) void {
	stderr.print(error_tag, .{}) catch {};

	const fmt_indented: []const u8 = comptime fmt_indented: {
		var it = std.mem.tokenizeScalar(u8, fmt, '\n');
		const spaces: ["error: ".len]u8 = @splat(' ');

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
