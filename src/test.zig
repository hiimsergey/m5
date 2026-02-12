const std = @import("std");
const parser = @import("parser.zig");

const Map = std.StringHashMap([]const u8);

const expect = std.testing.expect;
const expectError = std.testing.expectError;
const parse = parser.parse;

const gpa = std.testing.allocator;

const M5 = "zig-out/bin/m5";
const TESTFILE = ".zig-cache/test.txt";
var buf: [1024]u8 = undefined;

fn validate(condition: []const u8) !void {
	return parser.validate(condition, TESTFILE, 0);
}

/// Set `content` as the file content of the test file at `TESTFILE`
/// and return a file handle.
fn set_test_file(content: []const u8) !std.fs.File {
	var result = try std.fs.cwd().createFile(
		TESTFILE,
		.{ .read = true, .truncate = true }
	);

	var writer = result.writer(&buf);
	try writer.interface.writeAll(content);
	try writer.interface.flush();

	return result;
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
	
	fn expect_result(self: *const Command, ret: u8, cmp: []const u8) !void {
		try std.testing.expectEqual(ret, self.term.Exited);
		try std.testing.expectEqualStrings(cmp, self.stdout.items);
	}
};

test "Processing files normally" {
	var file = try set_test_file(
		\\m5 if ALICE
		\\hi alice
		\\m5 end
		\\
	);
	defer file.close();

	var c0 = try Command.init(&.{M5, "-p", "m5", TESTFILE});
	defer c0.deinit();
	try c0.expect_result(0, "");

	var c1 = try Command.init(&.{M5, "-p", "m5", "-DALICE", TESTFILE});
	defer c1.deinit();
	try c1.expect_result(0, "hi alice\n");

	var c2 = try Command.init(&.{M5, "-p", "m5", TESTFILE, "-DALICE"});
	defer c2.deinit();
	try c2.expect_result(0, "hi alice\n");

	var c3 = try Command.init(&.{M5, TESTFILE, "-DALICE", "-p", "m5"});
	defer c3.deinit();
	try c3.expect_result(1, "");

	var c4 = try Command.init(&.{M5, TESTFILE, "-DALICE"});
	defer c4.deinit();
	try c4.expect_result(1, "");
}

test "Processing files without trailing newline" {
	var file = try set_test_file(
		\\m5 if ALICE
		\\hi alice
		\\m5 end
	);
	defer file.close();

	var c0 = try Command.init(&.{M5, "-p", "m5", TESTFILE});
	defer c0.deinit();
	try c0.expect_result(0, "");

	var c1 = try Command.init(&.{M5, "-p", "m5", "-DALICE", TESTFILE});
	defer c1.deinit();
	try c1.expect_result(0, "hi alice\n");

	var c2 = try Command.init(&.{M5, "-p", "m5", TESTFILE, "-DALICE"});
	defer c2.deinit();
	try c2.expect_result(0, "hi alice\n");

	var c4 = try Command.init(&.{M5, TESTFILE, "-DALICE"});
	defer c4.deinit();
	try c4.expect_result(1, "");
}

test "Invalid if-block scoping" {
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
	// TODO NOW
	var file = try set_test_file(
		\\m5 if ALICE
		\\m5 if BOB
		\\m5 end
		\\m5 end
		\\
	);
	defer file.close();
}

test {
	var file = try set_test_file(
		\\m5 if ALICE
		\\hi alice
		\\m5 end
		\\
	);
	defer file.close();

	var c0 = try Command.init(&.{M5, "-p", "m5", TESTFILE});
	defer c0.deinit();
	try c0.expect_result(0, "");

	var c1 = try Command.init(&.{M5, "-p", "m5", "-DALICE", TESTFILE});
	defer c1.deinit();
	try c1.expect_result(0, "hi alice\n");

	var c2 = try Command.init(&.{M5, "-p", "m5", TESTFILE, "-DALICE"});
	defer c2.deinit();
	try c2.expect_result(0, "hi alice\n");
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
