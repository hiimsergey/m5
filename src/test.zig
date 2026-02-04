const std = @import("std");
const parser = @import("parser.zig");

const Map = std.StringHashMap([]const u8);

const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;
const parse = parser.parse;

const gpa = std.testing.allocator;

const M5 = "zig-out/bin/m5";
const TESTFILE = "test.txt";
var buf: [1024]u8 = undefined;

fn validate(condition: []const u8) !void {
	return parser.validate(condition, TESTFILE, 0);
}

/// Create a temporary file with `content` as the file content and return the relative
/// file path.
fn testFile(tmpdir: *std.testing.TmpDir, content: []const u8) ![]const u8 {
	var file = try tmpdir.dir.createFile(TESTFILE, .{ .read = true, .truncate = true });
	defer file.close();

	var writer = file.writer(&buf);
	try writer.interface.writeAll(content);
	try writer.interface.flush();

	return try std.mem.concat(
		gpa, u8,
		&.{".zig-cache/tmp/", &tmpdir.sub_path, "/", TESTFILE}
	);
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
	
	fn expectStdoutEq(self: *const Command, cmp: []const u8) !void {
		try std.testing.expectEqual(0, self.term.Exited);
		try std.testing.expectEqualStrings(cmp, self.stdout.items);
	}
};

test {
	var tmpdir: std.testing.TmpDir = std.testing.tmpDir(.{});
	defer tmpdir.cleanup();

	const filepath = try testFile(&tmpdir,
		\\m5 if ALICE
		\\hi alice
		\\m5 end
		\\
	);
	defer gpa.free(filepath);

	var c0 = try Command.init(&.{M5, "-p", "m5", filepath});
	try c0.expectStdoutEq("");
	c0.deinit();

	var c1 = try Command.init(&.{M5, "-p", "m5", "-DALICE", filepath});
	try c1.expectStdoutEq("hi alice\n");
	c1.deinit();

	var c2 = try Command.init(&.{M5, "-p", "m5", filepath, "-DALICE"});
	try c2.expectStdoutEq("hi alice\n");
	c2.deinit();
}

test {
	var tmpdir: std.testing.TmpDir = std.testing.tmpDir(.{});
	defer tmpdir.cleanup();

	const filepath = try testFile(&tmpdir,
		\\m5 if ALICE
		\\hi alice
		\\m5 end
	);
	defer gpa.free(filepath);

	var c0 = try Command.init(&.{M5, "-p", "m5", filepath});
	try c0.expectStdoutEq("");
	c0.deinit();

	var c1 = try Command.init(&.{M5, "-p", "m5", "-DALICE", filepath});
	try c1.expectStdoutEq("hi alice\n");
	c1.deinit();

	var c2 = try Command.init(&.{M5, "-p", "m5", filepath, "-DALICE"});
	try c2.expectStdoutEq("hi alice\n");
	c2.deinit();
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

	try expectEqual(parse("5 > 2 & 1 & 0", &map), false);
	try expectEqual(parse("!FOO", &map), true);
}

test "Condition parsing: Logic chains" {
	var map = Map.init(gpa);
	defer map.deinit();

	try map.put("A", "1");
	try map.put("B", "1");
	try map.put("C", "0");
	try expectEqual(parse("A & B | C", &map), true);

	map.clearRetainingCapacity();
	try map.put("A", "1");
	try map.put("B", "1");
	try map.put("C", "0");
	try expectEqual(parse("A | B & C", &map), true);
}

test "Condition parsing: AND" {
	var map = Map.init(gpa);
	defer map.deinit();

	try map.put("A", "1");
	try map.put("B", "1");
	try map.put("C", "0");
	try expectEqual(parse("A & B & C", &map), false);
}

test "Condition parsing: OR" {
	var map = Map.init(gpa);
	defer map.deinit();

	try map.put("FOO", "1");
	try map.put("BAR", "0");
	try map.put("BAZ", "0");
	try expectEqual(parse("FOO | BAR | BAZ", &map), true);

	map.clearRetainingCapacity();
	try map.put("FOO", "0");
	try map.put("BAR", "1");
	try map.put("BAZ", "0");
	try expectEqual(parse("FOO | BAR | BAZ", &map), true);

	map.clearRetainingCapacity();
	try map.put("FOO", "0");
	try map.put("BAR", "0");
	try map.put("BAZ", "1");
	try expectEqual(parse("FOO | BAR | BAZ", &map), true);
}

test "Condition parsing: Comparing" {
	var map = Map.init(gpa);
	defer map.deinit();

	try map.put("A", "1");
	try map.put("B", "0");
	try expectEqual(parse("A != B", &map), true);
}
