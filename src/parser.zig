const std = @import("std");
const a = @import("alias.zig");
const expectError = std.testing.expectError;
const expectEqual = std.testing.expectEqual;

const StringHashMap = std.StringHashMap;
const M5Error = @import("error.zig").M5Error;

const ParseState = enum(u8) {
	in_expression,
	in_number,
	expecting_expression,
	expecting_operator
};

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

pub fn validate(condition: []const u8, input: []const u8, linenr: usize) !void {
	var indentation_level: usize = 0;
	var state = ParseState.expecting_expression;
	var cur_numeric_literal: []const u8 = "";

	var i: usize = 1; // We define it outside the loop so we can skip characters.
	while (i < condition.len) : (i += 1) {
		// TODO FINAL remove the extra scope between while and switch
		switch (condition[i]) {
			' ' => switch (state) {
				.in_expression => state = .expecting_operator,
				.in_number => {
					state = .expecting_operator;

					// TODO FINAL TEST
					try check_overflow(cur_numeric_literal[0..i], input, linenr);
					cur_numeric_literal = "";
				},
				else => continue
			},
			'(' => switch (state) {
				.expecting_expression => indentation_level += 1,
				else => return M5Error.InvalidConditionSyntax
			},
			')' => {
				if (indentation_level == 0 or
					(state != .in_expression and state != .in_number))
						return M5Error.InvalidConditionSyntax;
				if (state == .in_number) {
					try check_overflow(cur_numeric_literal, input, linenr);
					cur_numeric_literal = "";
				}
				indentation_level -= 1;
				state = .expecting_operator;
			},
			'-' => switch (state) {
				.expecting_expression => state = .in_number,
				else => return M5Error.InvalidConditionSyntax
			},
			'0'...'9' => switch (state) {
				.expecting_expression => {
					state = .in_number;
					cur_numeric_literal = condition[i..];
				},
				.in_expression, .in_number => continue,
				.expecting_operator => return M5Error.InvalidConditionSyntax
			},
			'a'...'z', 'A'...'Z', '_' => switch (state) {
				.in_expression => continue,
				.expecting_expression => state = .in_expression,
				.in_number, .expecting_operator =>
					return M5Error.InvalidConditionSyntax
			},
			'&', '|', '=' => switch (state) {
				.expecting_expression => return M5Error.InvalidConditionSyntax,
				.in_expression, .in_number => state = .expecting_expression,
				.expecting_operator => state = .expecting_expression
			},
			'<', '>' => {
				switch (state) {
					.expecting_expression => return M5Error.InvalidConditionSyntax,
					.in_expression, .in_number => {
						if (indentation_level > 0) return M5Error.InvalidConditionSyntax;
						state = .expecting_expression;
					},
					.expecting_operator => state = .expecting_expression
				}
				if (i == condition.len - 1 and condition[i + 1] == '=') i += 1;
			},
			'!' => switch (state) {
				.expecting_expression => continue,
				.in_expression, .in_number => return M5Error.InvalidConditionSyntax,
				.expecting_operator => {
					if (i == condition.len - 1 or condition[i + 1] != '=') {
						a.errln(
							"{s}: line {d}: Expected operator, found '!' !",
							.{input, linenr}
						);
						return M5Error.InvalidConditionSyntax;
					}
					i += 1;
					state = .expecting_expression;
				}
			},
			else => return M5Error.InvalidConditionSyntax
		}
	}

	if (indentation_level > 0 or (state != .in_expression and state != .in_number))
		return M5Error.InvalidConditionSyntax;
}

pub fn parse(condition: []const u8, macros: *const StringHashMap([]const u8)) bool {
	std.debug.print("TODO parse '{s}'\n", .{condition});
	return parse_or(condition, macros);
}

fn parse_or(condition: []const u8, macros: *const StringHashMap([]const u8)) bool {
	std.debug.print("TODO parse_or '{s}'\n", .{condition});
	var result = false;
	var iter = ConditionSplit.init(condition, '|');

	while (iter.next()) |slice| {
		const parse_result = if (slice[0] == '(') parse(slice[1..], macros)
			else parse_and(slice, macros);
		result = result or parse_result;
	}
	return result;
}

fn parse_and(condition: []const u8, macros: *const StringHashMap([]const u8)) bool {
	std.debug.print("TODO parse_and '{s}'\n", .{condition});
	var result = true;
	var iter = ConditionSplit.init(condition, '&');

	while (iter.next()) |slice| {
		const parse_result = if (slice[0] == '(') parse(slice[1..], macros)
			else parse_cmp(slice, macros);
		result = result and parse_result;
	}
	return result;
}

fn parse_cmp(condition: []const u8, macros: *const StringHashMap([]const u8)) bool {
	std.debug.print("TODO parse_cmp '{s}'\n", .{condition});
	for (0..condition.len) |i| {
		switch (condition[i]) {
			'>' => {
				const lhs = a.parse(term_value(condition[0..i], macros)) catch 1;

				if (condition[i + 1] == '=') {
					const rhs = a.parse(term_value(condition[i + 2..], macros)) catch 1;
					return lhs >= rhs;
				}
				const rhs = a.parse(term_value(condition[i + 1..], macros)) catch 1;
				return lhs > rhs;
			},
			'<' => {
				const lhs = a.parse(term_value(condition[0..i], macros)) catch 1;

				if (condition[i + 1] == '=') {
					const rhs = a.parse(term_value(condition[i + 2..], macros)) catch 1;
					return lhs <= rhs;
				}
				const rhs = a.parse(term_value(condition[i + 1..], macros)) catch 1;
				return lhs < rhs;
			},
			'=' => {
				const lhs = a.parse(term_value(condition[0..i], macros)) catch 1;
				const rhs = a.parse(term_value(condition[i + 1..], macros)) catch 1;
				return lhs == rhs;
			},
			'!' => {
				const lhs = a.parse(term_value(condition[0..i], macros)) catch 1;
				const rhs = a.parse(term_value(condition[i + 2..], macros)) catch 1;
				return lhs != rhs;
			},
			else => continue
		}
	}
	const value = term_value(condition, macros);
	const numeric_value = a.parse(value) catch 1;
	return numeric_value > 0;
}

fn term_value(term: []const u8, macros: *const StringHashMap([]const u8)) []const u8 {
	const trim_nots = a.trimleft(term, "!");
	const negate: bool = (term.len - trim_nots.len) & 1 == 1;

	const trimmed = std.mem.trim(u8, trim_nots, " \t");
	std.debug.print("TODO term_value '{s}'\n", .{trimmed});

	const tmp_result = if (is_number(trimmed)) trimmed
		else macros.get(trimmed) orelse "0";
	if (!negate) return tmp_result;

	const literal_value = a.parse(trimmed) catch {
		const macro_value = macros.get(trimmed) orelse return "";
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

/// Return whether the given string could be successfully parsed into a number.
/// Ignores underscore characters, just like `std.fmt.parseInt` does.
fn is_number(buf: []const u8) bool {
	for (buf) |c| switch (c) {
		'0'...'9', '_' => continue,
		else => return false
	};
	return true;
}

/// Return `M5Error.InvalidConditionSyntax` if `buf` couldn't be
/// parsed into a i32.
/// `input` and `linenr` are just information about the string's position
/// for a more helpful error message.
fn check_overflow(buf: []const u8, input: []const u8, linenr: usize) !void {
	_ = a.parse(buf) catch {
		a.errln(
			"{s}: line {d}: " ++
			"The absolute value of {s} is too big to represent!",
			.{input, linenr, buf}
		);
		return M5Error.InvalidConditionSyntax;
	};
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
	try expectEqual(parse("5 > 2 & 1 & 0"), false);
	try expectEqual("!FOO", true);
}

test "Condition parsing: Logic chains" {
	var map = std.StringHashMap([]const u8).init(std.testing.allocator);
	defer map.deinit();

	try map.put("A", 1);
	try map.put("B", 1);
	try map.put("C", 0);
	try expectEqual(parse("A & B | C"), true);

	map.clearRetainingCapacity();
	try map.put("A", 1);
	try map.put("B", 1);
	try map.put("C", 0);
	try expectEqual(parse("A | B & C"), true);
}

test "Condition parsing: AND" {
	var map = std.StringHashMap([]const u8).init(std.testing.allocator);
	defer map.deinit();

	try map.put("A", 1);
	try map.put("B", 1);
	try map.put("C", 0);
	try expectEqual(parse("A & B & C"), false);
}

test "Condition parsing: OR" {
	var map = std.StringHashMap([]const u8).init(std.testing.allocator);
	defer map.deinit();

	try map.put("FOO", 1);
	try map.put("BAR", 0);
	try map.put("BAZ", 0);
	try expectEqual(parse("FOO | BAR | BAZ"), true);

	map.clearRetainingCapacity();
	try map.put("FOO", 0);
	try map.put("BAR", 1);
	try map.put("BAZ", 0);
	try expectEqual(parse("FOO | BAR | BAZ"), true);

	map.clearRetainingCapacity();
	try map.put("FOO", 0);
	try map.put("BAR", 0);
	try map.put("BAZ", 1);
	try expectEqual(parse("FOO | BAR | BAZ"), true);
}

test "Condition parsing: Comparing" {
	var map = std.StringHashMap([]const u8).init(std.testing.allocator);
	defer map.deinit();

	try map.put("A", 1);
	try map.put("B", 0);
	try expectEqual(parse("A != B"), true);
}
