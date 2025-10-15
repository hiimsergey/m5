const std = @import("std");

var stdout_buf: [1024]u8 = undefined;
pub var stdout = std.fs.File.stdout().writer(&stdout_buf);

pub fn contains_str(haystack: []const []const u8, needle: []const u8) bool {
	for (haystack) |hay| if (eql(hay, needle)) return true;
	return false;
}
pub fn eql(a: []const u8, b: []const u8) bool {
	return std.mem.eql(u8, a, b);
}
pub fn startswith(a: []const u8, b: []const u8) bool {
	return std.mem.startsWith(u8, a, b);
}
pub fn trimleft(slice: []const u8, trim: []const u8) []const u8 {
	return std.mem.trimLeft(u8, slice, trim);
}

pub fn flush() void {
	stdout.interface.flush() catch {};
}
pub fn print_help() void {
	println(
		\\m5 – a simplified text file preprocessor
		\\by Sergey Lavrent (https://github.com/hiimsergey/m5)
		\\v0.0.0  GPL-3.0
		\\
		\\Usage:
		\\    m5 (INPUTS | OPTION)...
		\\
		\\Inputs:
		\\    Absolute or relative paths to file to be preprocessed.
		\\    Multiple files can be passed to preprocess them one after another.
		\\
		\\Options:
		\\    -D[MACRO]=[VALUE]
		\\        Defines a new macro with [MACRO] as the name and [VALUE]
		\\        as the string value. If =[VALUE] is omitted, then the macro acts
		\\        as a boolean set to true.
		\\    -p [PREFIX]
		\\        Sets [PREFIX] as the line prefix. The preprocessor reads
		\\        lines starting with the prefix (disregarding leading whitespace
		\\        though) for m5 syntax.
		\\    -o [OUTPUT]
		\\        Sets [OUTPUT] as the destination file the preprocessed text
		\\        of all inputs given prior. After this, new inputs can be passed
		\\        for another output. If no output is given at all, the result is
		\\        written into stdout.
		\\    -v
		\\        Log every successfully preprocessed input.
		\\    -h, --help
		\\        Print this message.
		, .{}
	);
}
pub fn println(comptime fmt: []const u8, args: anytype) void {
	stdout.interface.print(fmt ++ "\n", args) catch {};
}
pub fn errln(comptime msg: []const u8) void {
	var stderr_buf: [1024]u8 = undefined;
	var stderr = std.fs.File.stderr().writer(&stderr_buf);
	stderr.interface.print(msg, .{}) catch {};
	stderr.interface.flush() catch {};
}
