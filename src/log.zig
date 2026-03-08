const std = @import("std");

const File = std.fs.File;

// TODO make error tag bold
const error_tag = "\x1b[31merror\x1b[0m: ";

var stderr_buf: [64]u8 = undefined;
var stderr_wrapper = File.stderr().writer(&stderr_buf);

pub const stderr = &stderr_wrapper.interface;

// TODO FINAL CONSIDER keep
pub fn err(comptime fmt: []const u8, args: anytype) void {
	stderr.print(error_tag, .{}) catch {};
	stderr.print(fmt ++ "\n", args) catch {};
}

pub fn errWithHelp(comptime fmt: []const u8, args: anytype) void {
	stderr.print(error_tag, .{}) catch {};
	stderr.print(fmt ++ "\n", args) catch {};
	stderr.print("See `lt --help` for correct usage!\n", .{}) catch {};
}

pub fn errWithLineNr(
	linenr: usize,
	comptime fmt: []const u8,
	args: anytype
) void {
	stderr.print(error_tag, .{}) catch {};
	stderr.print("line {d}: ", .{linenr}) catch {};
	stderr.print(fmt ++ "\n", args) catch {};
}
