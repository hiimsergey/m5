const std = @import("std");

var stderr_buf: [1024]u8 = undefined;
var stdout_buf: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);

pub const stdout = &stdout_writer.interface;
pub const stderr = &stderr_writer.interface;

pub const error_tag = "\x1b[31merror: ";
pub const style_reset = "\x1b[0m\n";
pub const help_text =
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
	\\
;

pub fn err(comptime fmt: []const u8, args: anytype) void {
	stderr.print(error_tag, .{}) catch {};
	stderr.print(fmt, args) catch {};
	stderr.print(style_reset, .{}) catch {};
}
