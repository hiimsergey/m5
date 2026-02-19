const std = @import("std");
const parser = @import("parser.zig");

const Map = std.StringHashMap([]const u8);

const expect = std.testing.expect;
const expectError = std.testing.expectError;
const parse = parser.parse;

const gpa = std.testing.allocator;

const m5 = "zig-out/bin/m5";
const test_file_path = ".zig-cache/test.txt";
var test_file: std.fs.File = undefined;
var test_file_writer: std.fs.File.Writer = undefined;
var test_file_writer_buf: [1024]u8 = undefined;

fn validate(condition: []const u8) !void {
	return parser.validate(condition, test_file_path, 0);
}

/// Open file at `test_file_path` for writing.
/// Must be closed with `test_file_path.close()`.
fn openTestFile() !void {
	test_file = try std.fs.cwd().createFile(
		test_file_path,
		.{ .read = true, .truncate = false }
	);
	test_file_writer = test_file.writer(&test_file_writer_buf);
}

/// Set `content` as the file content of the test file at `test_file_path`.
fn setTestFile(content: []const u8) !void {
	try test_file.setEndPos(0);
	try test_file_writer.interface.writeAll(content);
	try test_file_writer.interface.flush();
}

const Command = struct {
	child: std.process.Child,
	term: std.process.Child.Term,
	stdout: std.ArrayList(u8),
	stderr: std.ArrayList(u8),

	fn init(args: []const []const u8) !Command {
		var result: Command = undefined;

		result.child = std.process.Child.init(args, gpa);
		result.child.stdout_behavior = .Pipe;
		result.child.stderr_behavior = .Pipe;
		try result.child.spawn();

		result.stdout = std.ArrayList(u8).empty;
		result.stderr = std.ArrayList(u8).empty;

		try result.child.collectOutput(
			gpa,
			&result.stdout, &result.stderr,
			std.math.maxInt(usize)
		);

		result.term = try result.child.wait();
		return result;
	}

	fn deinit(self: *Command) void {
		self.stdout.deinit(gpa);
		self.stderr.deinit(gpa);
	}
	
	fn expectResult(self: *const Command, ret: u8, stdout: []const u8) !void {
		try std.testing.expectEqual(ret, self.term.Exited);
		try std.testing.expectEqualStrings(stdout, self.stdout.items);
	}
};

test "Processing files normally" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if ALICE
		\\hi alice
		\\m5 end
		\\
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", test_file_path});
	defer c0.deinit();
	try c0.expectResult(0, "");

	var c1 = try Command.init(&.{m5, "-p", "m5", "-DALICE", test_file_path});
	defer c1.deinit();
	try c1.expectResult(0, "hi alice\n");

	var c2 = try Command.init(&.{m5, "-p", "m5", test_file_path, "-DALICE"});
	defer c2.deinit();
	try c2.expectResult(0, "hi alice\n");

	var c3 = try Command.init(&.{m5, test_file_path, "-DALICE", "-p", "m5"});
	defer c3.deinit();
	try c3.expectResult(1, "");

	var c4 = try Command.init(&.{m5, test_file_path, "-DALICE"});
	defer c4.deinit();
	try c4.expectResult(1, "");
}

test "Processing files without trailing newline" {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if ALICE
		\\hi alice
		\\m5 end
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", test_file_path});
	defer c0.deinit();
	try c0.expectResult(0, "");

	var c1 = try Command.init(&.{m5, "-p", "m5", "-DALICE", test_file_path});
	defer c1.deinit();
	try c1.expectResult(0, "hi alice\n");

	var c2 = try Command.init(&.{m5, "-p", "m5", test_file_path, "-DALICE"});
	defer c2.deinit();
	try c2.expectResult(0, "hi alice\n");

	var c4 = try Command.init(&.{m5, test_file_path, "-DALICE"});
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

	try setTestFile(
		\\foo bar
		\\m5 else
		\\baz buzz
		\\m5 end
	);

	var c1 = try Command.init(&.{m5, "-p", "m5", test_file_path});
	defer c1.deinit();
	try c1.expectResult(1, "");
	// TODO TEST missing if
	// TODO TEST missing end
	// TODO TEST too much end
}

test "Else keyword" {
	// TODO TEST else
	// TODO TEST elsefoobar
	// TODO TEST else foobar
	// TODO TEST else if condition
}

test "Nested if-blocks" {
	try openTestFile();
	defer test_file.close();

	const cmd = [_][]const u8{m5, "-p", "m5", "-DALICE", "-DBOB", test_file_path};

	// TODO NOW
	try setTestFile(
		\\m5 if ALICE
		\\m5 if BOB
		\\hi alice and bob
		\\m5 end
		\\m5 end
		\\
	);

	var c0 = try Command.init(&cmd);
	defer c0.deinit();
	try c0.expectResult(0, "hi alice and bob\n");

	try setTestFile(
		\\m5 if ALICE
		\\m5 if BOB
		\\hi alice and bob
		\\m5 end
		\\
	);

	var c1 = try Command.init(&cmd);
	defer c1.deinit();
	try c1.expectResult(1, "");

	// TODO NOW
	// TODO TEST missing if
	// TODO TEST missing end
	// TODO TEST too much end
}

test {
	try openTestFile();
	defer test_file.close();

	try setTestFile(
		\\m5 if ALICE
		\\hi alice
		\\m5 end
		\\
	);

	var c0 = try Command.init(&.{m5, "-p", "m5", test_file_path});
	defer c0.deinit();
	try c0.expectResult(0, "");

	var c1 = try Command.init(&.{m5, "-p", "m5", "-DALICE", test_file_path});
	defer c1.deinit();
	try c1.expectResult(0, "hi alice\n");

	var c2 = try Command.init(&.{m5, "-p", "m5", test_file_path, "-DALICE"});
	defer c2.deinit();
	try c2.expectResult(0, "hi alice\n");
}

test "Condition validation" {
	// TODO PLAN
	// maybe store all tests in an array
	// and use it to both validate and run tests
	// or write a function that does both validation and testing
	try validate("a & b | c");
	try validate("a & (b & c) | d | (a | (b & c))");
	try validate("(((b)))");
	try validate("a < 5");
	try validate("a < b < c"); // (0|1) < c
	try validate("a != b");

	const E = error.Generic;
	try expectError(E, validate("a |"));
	try expectError(E, validate("a ! b"));
	try expectError(E, validate("2bad"));
}

test "Condition parsing: Literals" {
	var map = Map.init(gpa);
	defer map.deinit();

	try expect(!parse("5 > 2 & 1 & 0", &map));
	try expect(parse("!FOO", &map));
}

test "Condition parsing: Logic chains" {
	var map = Map.init(gpa);
	defer map.deinit();

	try map.put("A", "1");
	try map.put("B", "1");
	try map.put("C", "0");
	try expect(parse("A & B | C", &map));

	map.clearRetainingCapacity();
	try map.put("A", "1");
	try map.put("B", "1");
	try map.put("C", "0");
	try expect(parse("A | B & C", &map));
}

test "Condition parsing: AND" {
	var map = Map.init(gpa);
	defer map.deinit();

	try map.put("A", "1");
	try map.put("B", "1");
	try map.put("C", "0");
	try expect(!parse("A & B & C", &map));
}

test "Condition parsing: OR" {
	var map = Map.init(gpa);
	defer map.deinit();

	try map.put("FOO", "1");
	try map.put("BAR", "0");
	try map.put("BAZ", "0");
	try expect(parse("FOO | BAR | BAZ", &map));

	map.clearRetainingCapacity();
	try map.put("FOO", "0");
	try map.put("BAR", "1");
	try map.put("BAZ", "0");
	try expect(parse("FOO | BAR | BAZ", &map));

	map.clearRetainingCapacity();
	try map.put("FOO", "0");
	try map.put("BAR", "0");
	try map.put("BAZ", "1");
	try expect(parse("FOO | BAR | BAZ", &map));
}

test "Condition parsing: Comparing" {
	var map = Map.init(gpa);
	defer map.deinit();

	try map.put("A", "1");
	try map.put("B", "0");
	try expect(parse("A != B", &map));
}
