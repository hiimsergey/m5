const std = @import("std");
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;

const M5Error = @import("error.zig").M5Error;

const State = enum(u8) {
	InExpression,
	InNumber,
	ExpectingExpression,
	ExpectingOperator
};

pub fn validate(condition: []const u8) !void {
	var indentation_level: usize = 0;
	var state = State.ExpectingExpression;

	var i: usize = 0;
	while (i < condition.len) : (i += 1) {
		switch (condition[i]) {
			' ' => {
				if (state == .InExpression) state = .ExpectingOperator;
			},
			'(' => {
				if (state == .InExpression or state == .ExpectingOperator)
					return M5Error.InvalidConditionSyntax;
				indentation_level += 1;
			},
			')' => {
				if (indentation_level == 0 or
					state != .InExpression) return M5Error.InvalidConditionSyntax;
				indentation_level -= 1;
			},
			'0'...'9' => {
				switch (state) {
					.ExpectingExpression => state = .InNumber,
					.InExpression, .InNumber => continue,
					.ExpectingOperator => return M5Error.InvalidConditionSyntax
				}
			},
			'a'...'z', 'A'...'Z', '_', '-' => {
				switch (state) {
					.InExpression => continue,
					.ExpectingExpression => state = .InExpression,
					.InNumber, .ExpectingOperator =>
						return M5Error.InvalidConditionSyntax
				}
			},
			'&', '|', '=' => {
				switch (state) {
					.ExpectingExpression => return M5Error.InvalidConditionSyntax,
					.InExpression, .InNumber => {
						if (indentation_level > 0) return M5Error.InvalidConditionSyntax;
						state = .ExpectingExpression;
					},
					.ExpectingOperator => state = .ExpectingExpression
				}
			},
			'<', '>' => {
				switch (state) {
					.ExpectingExpression => return M5Error.InvalidConditionSyntax,
					.InExpression, .InNumber => {
						if (indentation_level > 0) return M5Error.InvalidConditionSyntax;
						state = .ExpectingExpression;
					},
					.ExpectingOperator => state = .ExpectingExpression
				}
				if (condition[i + 1] == '=') i += 1;
			},
			'!' => {
				if (condition[i + 1] != '=') return M5Error.InvalidConditionSyntax;
				i += 1;
				switch (state) {
					.ExpectingExpression => return M5Error.InvalidConditionSyntax,
					.InExpression, .InNumber => {
						if (indentation_level > 0) return M5Error.InvalidConditionSyntax;
						state = .ExpectingExpression;
					},
					.ExpectingOperator => state = .ExpectingExpression
				}
			},
			else => return M5Error.InvalidConditionSyntax
		}
	}

	// TODO handle variable negations: !A

	if (indentation_level > 0 or (state != .InExpression and state != .InNumber))
		return M5Error.InvalidConditionSyntax;
}

pub inline fn parse(condition: []const u8) bool {
	return try parse_or(condition) > 0;
}

fn parse_or(condition: []const u8) !u16 {
	// TODO NOW
	_ = condition;
}

test "Condition validation" {
	try validate("a & b | c");
	try validate("a & (b & c) | d | (a | (b & c))");
	try validate("(((b)))");
	try validate("a < 5");
	try validate("a < b < c");
	try validate("a != b");

	try expectError(M5Error.InvalidConditionSyntax, validate("a |"));
	try expectError(M5Error.InvalidConditionSyntax, validate("a ! b"));
	try expectError(M5Error.InvalidConditionSyntax, validate("2bad"));
}

test "Condition parsing: Literals" {
	try expectEqual(try parse("5 > 2 & 1 & 0"), false);
	try expectEqual("!FOO", true);
}

test "Condition parsing: Logic chains" {
	var map = std.StringHashMap(u16).init(std.testing.allocator);
	defer map.deinit();

	try map.put("A", 1);
	try map.put("B", 1);
	try map.put("C", 0);
	try expectEqual(try parse("A & B | C"), true);

	map.clearRetainingCapacity();
	try map.put("A", 1);
	try map.put("B", 1);
	try map.put("C", 0);
	try expectEqual(try parse("A | B & C"), true);
}

test "Condition parsing: AND" {
	var map = std.StringHashMap(u16).init(std.testing.allocator);
	defer map.deinit();

	try map.put("A", 1);
	try map.put("B", 1);
	try map.put("C", 0);
	try expectEqual(try parse("A & B & C"), false);
}

test "Condition parsing: OR" {
	var map = std.StringHashMap(u16).init(std.testing.allocator);
	defer map.deinit();

	try map.put("FOO", 1);
	try map.put("BAR", 0);
	try map.put("BAZ", 0);
	try expectEqual(try parse("FOO | BAR | BAZ"), true);

	map.clearRetainingCapacity();
	try map.put("FOO", 0);
	try map.put("BAR", 1);
	try map.put("BAZ", 0);
	try expectEqual(try parse("FOO | BAR | BAZ"), true);

	map.clearRetainingCapacity();
	try map.put("FOO", 0);
	try map.put("BAR", 0);
	try map.put("BAZ", 1);
	try expectEqual(try parse("FOO | BAR | BAZ"), true);
}

test "Condition parsing: Comparing" {
	var map = std.StringHashMap(u16).init(std.testing.allocator);
	defer map.deinit();

	try map.put("A", 1);
	try map.put("B", 0);
	try expectEqual(try parse("A != B"), true);
}
