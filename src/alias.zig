//! A module with function aliases (i.e. abstractions) and helper functions.

// TODO fragment this file into where they are needed
// RENAME to log.zig

const std = @import("std");

var stderr_buf: [1024]u8 = undefined;
var stdout_buf: [1024]u8 = undefined;
pub var stdout = std.fs.File.stdout().writer(&stdout_buf);
pub var stderr = std.fs.File.stderr().writer(&stderr_buf);

pub fn containsStr(haystack: []const []const u8, needle: []const u8) bool {
	for (haystack) |hay| if (eql(hay, needle)) return true;
	return false;
}
pub fn eql(a: []const u8, b: []const u8) bool {
	return std.mem.eql(u8, a, b);
}
pub fn startswith(a: []const u8, b: []const u8) bool {
	return std.mem.startsWith(u8, a, b);
}
pub fn parsei(buf: []const u8) !i32 {
	return std.fmt.parseInt(i32, buf, 10);
}
pub fn trimWsLeft(slice: []const u8) []const u8 {
	return std.mem.trimLeft(u8, slice, " \t");
}

// TODO REMOVE
pub fn println(comptime fmt: []const u8, args: anytype) void {
	stdout.interface.print(fmt ++ "\n", args) catch {};
}
// TODO REMOVE
pub fn errln(comptime msg: []const u8, args: anytype) void {
	stderr.interface.print(msg ++ "\n", args) catch {};
}
pub fn err(comptime msg: []const u8, args: anytype) void {
	stderr.interface.print(msg, args) catch {};
}
pub fn errtag() void {
	_ = stderr.interface.write("\x1b[31merror: ") catch {};
}
pub fn printHelp() void {
	println(
		\\m5 - a simple text file processor
		\\by Sergey Lavrent (https://github.com/hiimsergey/m5)
		\\v0.1.1  GPL-3.0
		\\
		\\Usage:
		\\    m5 (INPUTS | OPTION)...
		\\
		\\Inputs:
		\\    Absolute or relative paths to file to be processed.
		\\    Multiple files can be passed to process them one after another.
		\\
		\\Options:
		\\    -D[MACRO]=[VALUE]
		\\        Define a new macro with [MACRO] as the name and [VALUE]
		\\        as the string value. If =[VALUE] is omitted, then the macro acts
		\\        as a boolean set to true.
		\\    -p [PREFIX]
		\\        Set [PREFIX] as the line prefix. The processor reads
		\\        lines starting with the prefix (disregarding leading whitespace
		\\        though) for m5 syntax.
		\\    -o [OUTPUT]
		\\        Set [OUTPUT] as the destination file the processed text
		\\        of all inputs given prior. After this, new inputs can be passed
		\\        for another output. If no output is given at all, the result is
		\\        written into stdout.
		\\    -v
		\\        Log every successfully processed input.
		\\    -h, --help
		\\        Print this message.
		, .{}
	);
}
