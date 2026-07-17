const std = @import("std");
const parser = @import("parser.zig");

const ArrayList = std.ArrayList;
const Child = std.process.Child;
const Map = std.StringHashMap([]const u8);

const expect = std.testing.expect;
const expectError = std.testing.expectError;
const parse = parser.parse;

const gpa = std.testing.allocator;
const io = std.testing.io;
const m5 = "zig-out/bin/m5";
const test_file_path = ".zig-cache/test.txt";
var test_file: std.Io.File = undefined;
var test_file_writer: std.Io.File.Writer = undefined;
var test_file_writer_buf: [1024]u8 = undefined;

/// Creates new `Command` instances with these commands.
/// Uses allocator internally (bad practice but probably not that bad in a testing file).
fn expectCommand(
	comptime args: []const u8,
	arg_args: anytype,
	ret: u8,
	expd_stdout: []const u8) !void
{
	const argv: []const []const u8 = comptime argv: {
		var result: []const []const u8 = &.{};
		var it = std.mem.tokenizeAny(u8, std.fmt.comptimePrint(args, arg_args), " \t");
		while (it.next()) |arg| result = result ++ &.{arg};
		break :argv result;
	};
	const run_result: std.process.RunResult = std.process.run(gpa, io, .{ .argv = argv });
	try std.testing.expectEqual(ret, run_result.term.exited);
	try std.testing.expectEqualStrings(expd_stdout, run_result.stdout);
	gpa.free(run_result.stdout);
	gpa.free(run_result.stderr);
}

/// Opens file at `test_file_path` for writing.
/// Must be closed with `test_file_path.close()`.
fn openTestFile() !void {
	test_file = try std.fs.cwd().createFile(
		test_file_path,
		.{ .read = true, .truncate = false }
	);
	test_file_writer = test_file.writer(&test_file_writer_buf);
}

/// Sets `content` as the file content of the test file at `test_file_path`.
fn setTestFile(content: []const u8) !void {
	try test_file.setEndPos(0);
	try test_file_writer.interface.writeAll(content);
	try test_file_writer.interface.flush();
}

test "Processing files normally" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\hi alice
		\\m5 end
		\\
	);

	try expectCommand("{s} {s}", .{m5, test_file_path}, 0, "");
	try expectCommand("{s} {s} -p:m5", .{m5, test_file_path}, 0, "");
	try expectCommand("{s} {s} -d:alice", .{m5, test_file_path}, 0, "hi alice\n");
	try expectCommand("{s} -d:alice {s}", .{m5, test_file_path}, 0, "hi alice\n");
}

test "Processing files without trailing newline" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\hi alice
		\\m5 end
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", test_file_path});
	defer c0.deinit();
	try c0.expectResult(0, "");

	var c1 = try Command.init(&.{m5, "-p", "m5", "-Dalice", test_file_path});
	defer c1.deinit();
	try c1.expectResult(0, "hi alice\n");

	var c2 = try Command.init(&.{m5, "-p", "m5", test_file_path, "-Dalice"});
	defer c2.deinit();
	try c2.expectResult(0, "hi alice\n");

	var c4 = try Command.init(&.{m5, test_file_path, "-Dalice"});
	defer c4.deinit();
	try c4.expectResult(1, "");
}

test "Invalid if-block scoping" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\foo bar
		\\m5 else
		\\baz buzz
		\\m5 end
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", test_file_path});
	defer c0.deinit();
	try c0.expectResult(1, "");
}

test "Else keyword - normal else" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\foo bar
		\\m5 else
		\\baz buzz
		\\m5 end
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", test_file_path});
	defer c0.deinit();
	try c0.expectResult(0, "baz buzz\n");
}

test "Else keyword - normal if" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\foo bar
		\\m5 else
		\\baz buzz
		\\m5 end
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", "-Dalice", test_file_path});
	defer c0.deinit();
	try c0.expectResult(0, "foo bar\n");
}

test "Else keyword - elsebob if" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\foo bar
		\\m5 elsebob
		\\baz buzz
		\\m5 end
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", "-Dalice", test_file_path});
	defer c0.deinit();
	try c0.expectResult(1, "");
}

test "Else keyword - elsebob else" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\foo bar
		\\m5 elsebob
		\\baz buzz
		\\m5 end
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", "-Dbob", test_file_path});
	defer c0.deinit();
	try c0.expectResult(1, "");
}

test "Else keyword - else bob else" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\foo bar
		\\m5 else bob
		\\baz buzz
		\\m5 end
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", "-Dbob", test_file_path});
	defer c0.deinit();
	try c0.expectResult(1, "");
}

test "Else keyword - else if bob else" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\foo bar
		\\m5 else if bob
		\\baz buzz
		\\m5 end
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", "-Dbob", test_file_path});
	defer c0.deinit();
	try c0.expectResult(0, "baz buzz\n");
}

test "Nested if-blocks - Correct" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\m5 if bob
		\\hi alice and bob
		\\m5 end
		\\m5 end
		\\
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", "-Dalice", "-Dbob", test_file_path});
	defer c0.deinit();
	try c0.expectResult(0, "hi alice and bob\n");

}

test "Nested if-blocks - missing end" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\m5 if bob
		\\hi alice and bob
		\\m5 end
		\\
	);

	var c1 = try Command.init(&.{m5, "-p", "m5", "-Dalice", "-Dbob", test_file_path});
	defer c1.deinit();
	try c1.expectResult(1, "");
}

test "Nested if-blocks - missing if" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\hi alice and bob
		\\m5 end
		\\
	);

	var c1 = try Command.init(&.{m5, "-p", "m5", "-Dalice", "-Dbob", test_file_path});
	defer c1.deinit();
	try c1.expectResult(1, "");
}

test "Nested if-blocks - too much end" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\m5 if bob
		\\hi alice and bob
		\\m5 end
		\\m5 end
		\\m5 end
		\\
	);

	var c1 = try Command.init(&.{m5, "-p", "m5", "-Dalice", "-Dbob", test_file_path});
	defer c1.deinit();
	try c1.expectResult(1, "");
}

test "Nested if-blocks - if and end at wrong pos 1" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\m5 end
		\\m5 end
		\\m5 if bob
		\\hi alice and bob
		\\
	);

	var c1 = try Command.init(&.{m5, "-p", "m5", "-Dalice", "-Dbob", test_file_path});
	defer c1.deinit();
	try c1.expectResult(1, "");
}

test "Nested if-blocks - if and end at wrong pos 2" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 end
		\\m5 if alice
		\\m5 end
		\\m5 if bob
		\\hi alice and bob
		\\
	);

	var c1 = try Command.init(&.{m5, "-p", "m5", "-Dalice", "-Dbob", test_file_path});
	defer c1.deinit();
	try c1.expectResult(1, "");
}

test "Nested if-blocks - if and end at wrong pos 3" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 end
		\\m5 end
		\\hi alice and bob
		\\m5 if alice
		\\m5 if bob
		\\
	);

	var c1 = try Command.init(&.{m5, "-p", "m5", "-Dalice", "-Dbob", test_file_path});
	defer c1.deinit();
	try c1.expectResult(1, "");
}

test {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if alice
		\\hi alice
		\\m5 end
		\\
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", test_file_path});
	defer c0.deinit();
	try c0.expectResult(0, "");

	var c1 = try Command.init(&.{m5, "-p", "m5", "-Dalice", test_file_path});
	defer c1.deinit();
	try c1.expectResult(0, "hi alice\n");

	var c2 = try Command.init(&.{m5, "-p", "m5", test_file_path, "-Dalice"});
	defer c2.deinit();
	try c2.expectResult(0, "hi alice\n");
}

// TODO PLAN new test structure
// condition parsing
//     parsing variables
//     parsing numbers
//         with _
//         with -
//         error on leading +
//         misplaced (
//         unopened )
//         misplaced )
//         misplaced -
//         number instead of operator
//         letter amidst number
//         ! amidst number
//         char instead of operator
//         _ instead of operator
//         operator instead of expression
//         cmp operator instead of expression
//         ! instead of operator
//         random character
//         unclosed parenthesis
//         expecting expression at end
// line parsing
//     nested m5 lines
//     invalid keyword
//     else without if
//     end without if
//     if without end
//     else if without end
//     else if invalidsequence
//     empty cmd
// cli parsing
//     couldnt open input file
//     -o without inputs
//     -o without outputs
//     -p without prefix
//     -D without define
//     -D-123
//     -D123
//     random flag
//     input without prefix
// (just go through every error message)
