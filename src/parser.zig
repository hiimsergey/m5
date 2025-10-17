const std = @import("std");
const a = @import("alias.zig");
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;

const StringHashMap = std.StringHashMap;
const M5Error = @import("error.zig").M5Error;

const State = enum(u8) {InExpression, InNumber, ExpectingExpression, ExpectingOperator};

// TODO FINAL write tests
const ConditionSplit = struct {
	expression: []const u8,
	token: u8,

	pub fn init(expression: []const u8, token: u8) ConditionSplit {
		return .{ .expression = expression, .token = token };
	}

	pub fn next(self: *ConditionSplit) ?[]const u8 {
		if (self.expression.len == 0) return null;
		self.expression = std.mem.trimLeft(u8, self.expression, " ");

		if (self.expression[0] == '(') return self.end_bracket();

		for (0..self.expression.len) |i| {
			if (self.expression[i] == self.token) {
				const result = self.expression[0..i];
				self.expression = self.expression[i + 1..];
				return result;
			}
		}
		const result = self.expression;
		self.expression = &.{};
		return result;
	}

	fn end_bracket(self: *ConditionSplit) []const u8 {
		var depth: usize = 1;
		for (1..self.expression.len) |i| switch (self.expression[i]) {
			'(' => depth += 1,
			')' => {
				depth -= 1;
				if (depth != 0) continue;

				if (self.expression[i] == self.token or i == self.expression.len - 1) {
					const result = self.expression[0..i];
					self.expression = self.expression[i + 1..];
					return result;
				}
			},
			else => continue
		};
		unreachable;
	}
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
				// TODO FIX no bounds checking
				if (condition[i + 1] == '=') i += 1;
			},
			'!' => {
				// TODO FIX no bounds checking
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
	// TODO check for error.Overflow in numbers

	if (indentation_level > 0 or (state != .InExpression and state != .InNumber))
		return M5Error.InvalidConditionSyntax;
}

pub fn parse(
	condition: []const u8,
	macros: *const StringHashMap([]const u8)
) M5Error!bool {
	return parse_or(condition, macros);
}

fn parse_or(
	condition: []const u8,
	macros: *const StringHashMap([]const u8)
) M5Error!bool {
	var result = false;
	var iter = ConditionSplit.init(condition, '|');

	while (iter.next()) |slice| {
		const parse_result = if (slice[0] == '(') try parse(slice[1..], macros)
			else try parse_and(slice, macros);
		result = result or parse_result;
	}
	return result;
}

fn parse_and(
	condition: []const u8,
	macros: *const StringHashMap([]const u8)
) M5Error!bool {
	var result = true;
	var iter = ConditionSplit.init(condition, '&');

	while (iter.next()) |slice| {
		const parse_result = if (slice[0] == '(') try parse(slice[1..], macros)
			else try parse_cmp(slice, macros);
		result = result and parse_result;
	}
	return result;
}

fn parse_cmp(
	condition: []const u8,
	macros: *const StringHashMap([]const u8)
) M5Error!bool {
	for (0..condition.len) |i| {
		switch (condition[i]) {
			'>' => {
				const lhs = a.parse(try term_value(condition[0..i], macros)) catch 1;

				if (condition[i + 1] == '=') {
					const rhs = a.parse(try term_value(condition[i + 2..], macros))
						catch 0;
					return lhs >= rhs;
				}
				const rhs = a.parse(try term_value(condition[i + 1..], macros))
					catch 0;
				return lhs > rhs;
			},
			'<' => {
				const lhs = a.parse(try term_value(condition[0..i], macros)) catch 1;

				if (condition[i + 1] == '=') {
					const rhs = a.parse(try term_value(condition[i + 2..], macros))
						catch 0;
					return lhs <= rhs;
				}
				const rhs = a.parse(try term_value(condition[i + 1..], macros))
					catch 0;
				return lhs < rhs;
			},
			'=' => {
				const lhs = a.parse(try term_value(condition[0..i], macros)) catch 1;
				const rhs = a.parse(try term_value(condition[i + 1..], macros)) catch 1;
				return lhs == rhs;
			},
			'!' => switch (condition[i + 1]) {
				' ' => return M5Error.InvalidConditionSyntax,
				'=' => {
					const lhs = a.parse(try term_value(condition[0..i], macros))
						catch 0;
					const rhs = a.parse(try term_value(condition[i + 2..], macros))
						catch 0;
					return lhs != rhs;
				},
				else => continue
			},
			else => continue
		}
	}
	const value = try term_value(condition, macros);
	const numeric_value = a.parse(value) catch 1;
	return numeric_value > 0;
}

// TODO this function should return strings
fn term_value(
	term: []const u8,
	macros: *const StringHashMap([]const u8)
) M5Error![]const u8 {
	if (term[0] != '!') {
		if (is_number(term)) return term;
		return macros.get(term) orelse "0";
	}

	const rest = term[1..];
	const literal_value = a.parse(rest) catch {
		const macro_value = macros.get(rest) orelse return "";
		const macro_literal_value = a.parse(macro_value) catch
			return "0";
		return switch (macro_literal_value) {
			0 => "",
			else => "0"
		};
	};
	return switch (literal_value) {
		0 => "",
		else => "0"
	};
}

fn is_number(buf: []const u8) bool {
	for (buf) |c| switch (c) {
		'0'...'9', '_' => continue,
		else => return false
	};
	return true;
}

// TODO FINAL FIX ALL tests
test "Condition validation" {
	try validate("a & b | c");
	try validate("a & (b & c) | d | (a | (b & c))");
	try validate("(((b)))");
	try validate("a < 5");
	try validate("a < b < c"); // (0|1) < c
	try validate("a != b");

	const ics = M5Error.InvalidConditionSyntax;
	try expectError(ics, validate("a |"));
	try expectError(ics, validate("a ! b"));
	try expectError(ics, validate("2bad"));
}

test "Condition parsing: Literals" {
	try expectEqual(try parse("5 > 2 & 1 & 0"), false);
	try expectEqual("!FOO", true);
}

test "Condition parsing: Logic chains" {
	var map = std.StringHashMap([]const u8).init(std.testing.allocator);
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
	var map = std.StringHashMap([]const u8).init(std.testing.allocator);
	defer map.deinit();

	try map.put("A", 1);
	try map.put("B", 1);
	try map.put("C", 0);
	try expectEqual(try parse("A & B & C"), false);
}

test "Condition parsing: OR" {
	var map = std.StringHashMap([]const u8).init(std.testing.allocator);
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
	var map = std.StringHashMap([]const u8).init(std.testing.allocator);
	defer map.deinit();

	try map.put("A", 1);
	try map.put("B", 0);
	try expectEqual(try parse("A != B"), true);
}
