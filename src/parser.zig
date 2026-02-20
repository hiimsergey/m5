const std = @import("std");
const log = @import("log.zig");

const StringHashMap = std.StringHashMap;

const E = error.Generic;

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
		self.expression = std.mem.trimStart(u8, self.expression, " ");

		if (self.expression[0] == '(') return self.endBracket();

		for (0..self.expression.len) |i| {
			if (self.expression[i] == self.token) {
				const result = self.expression[0..i];
				self.expression = self.expression[i + 1..];
				return result;
			}
		}

		const result = self.expression;
		self.expression = "";
		return result;
	}

	fn endBracket(self: *ConditionSplit) []const u8 {
		var scope: usize = 1;
		for (1..self.expression.len) |i| switch (self.expression[i]) {
			'(' => scope += 1,
			')' => {
				scope -= 1;
				if (scope != 0) continue;

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
	var scope: usize = 0;
	var state = ParseState.expecting_expression;
	var cur_numeric_literal: []const u8 = "";

	var i: usize = 0; // We define it outside the loop so we can skip characters.
	while (i < condition.len) : (i += 1) {
		// TODO FINAL remove the extra scope between while and switch
		switch (condition[i]) {
			' ', '\t' => switch (state) {
				.in_expression => state = .expecting_operator,
				.in_number => {
					state = .expecting_operator;

					// TODO FINAL TEST
					try checkOverflow(cur_numeric_literal[0..i], input, linenr);
					cur_numeric_literal = "";
				},
				else => continue
			},
			'(' => switch (state) {
				.expecting_expression => scope += 1,
				else => {
					log.err(
						"{s}, line {d}: Expected expression, got '(' !\n",
						.{input, linenr}
					);
					return E;
				}
			},
			')' => {
				//if (scope == 0 or (state != .in_expression and state != .in_number)) {
				if (scope == 0) {
					log.err(
						"{s}, line {d}: Unexpected ')' without opening bracket!\n",
						.{input, linenr}
					);
					return E;
				}
				switch (state) {
					.expecting_expression => {
						log.err(
							"{s}, line {d}: Expected expression, got ')' !\n",
							.{input, linenr}
						);
						return E;
					},
					.in_number => {
						try checkOverflow(cur_numeric_literal, input, linenr);
						cur_numeric_literal = "";
					},
					else => {
						scope -= 1;
						state = .expecting_operator;
					}
				}

				// TODO ADD test for \t characters
				// TODO ADD test for too much whitespace
				// TODO ADD test for mixed whitespace
			},
			'-' => switch (state) {
				.expecting_expression => state = .in_number,
				else => {
					log.err(
						"{s}, line {d}: invalid character '-' !\n",
						.{input, linenr}
					);
					return E;
				}
			},
			'0'...'9' => switch (state) {
				.expecting_expression => {
					state = .in_number;
					cur_numeric_literal = condition[i..];
				},
				.in_expression, .in_number => continue,
				.expecting_operator => {
					log.err(
						"{s}, line {d}: Expected operator, got number!\n",
						.{input, linenr}
					);
					return E;
				}
			},
			'a'...'z', 'A'...'Z' => switch (state) {
				.in_expression => continue,
				.expecting_expression => state = .in_expression,
				.in_number => {
					log.err(
						"{s}, line {d}: Unexpected letter '{}' in number!\n",
						.{input, linenr, condition[i]}
					);
					return E;
				},
				.expecting_operator => {
					log.err(
						"{s}, line {d}: Expected operator, got '{}' !\n",
						.{input, linenr, condition[i]}
					);
					return E;
				}
			},
			'_' => switch (state) {
				.in_expression, .in_number => continue,
				.expecting_expression => state = .in_expression,
				.expecting_operator => {
					log.err(
						"{s}, line {d}: Expected operator, got '_' !\n",
						.{input, linenr}
					);
					return E;
				}
				// TODO ADD test leading and trailing underscore in numbers
			},
			'&', '|', '=' => switch (state) {
				.expecting_expression => {
					log.err(
						"{s}, line {d}: Expected expression, got operator '{}' !\n",
						.{input, linenr, condition[i]}
					);
					return E;
				},
				else => state = .expecting_expression
			},
			'<', '>' => {
				switch (state) {
					.expecting_expression => {
						log.err(
							"{s}, line {d}: Expected expression, " ++
							"got comparison operator '{}' !\n",
							.{input, linenr, condition[i]}
						);
						return E;
					},
					else => state = .expecting_expression
				}
				if (i < condition.len - 1 and condition[i + 1] == '=') i += 1;
			},
			'!' => switch (state) {
				.expecting_expression => continue,
				.in_expression, .in_number => {
					log.err(
						"{s}, line {d}: Unexpected '!' in number!\n",
						.{input, linenr}
					);
					return E;
				},
				.expecting_operator => {
					if (i == condition.len - 1 or condition[i + 1] != '=') {
						log.err(
							"{s}, line {d}: Expected operator, found '!' !\n",
							.{input, linenr}
						);
						return E;
					}
					i += 1;
					state = .expecting_expression;
				}
			},
			else => {
				log.err(
					"{s}, line {d}: Expected operator, found '!' !\n",
					.{input, linenr}
				);
				return E;
			}
		}
	}

	// TODO NOW in order for trailing ) to work
	//if (scope > 0 or (state != .in_expression and state != .in_number)) {
	if (scope == 0 and state != .expecting_expression) return;
	log.err(
		"{s}, line {d}: Expected operator, found '!' !\n",
		.{input, linenr}
	);
	return E;
}

pub fn parse(condition: []const u8, macros: *const StringHashMap([]const u8)) bool {
	return parseOr(condition, macros);
}

fn parseOr(condition: []const u8, macros: *const StringHashMap([]const u8)) bool {
	var result = false;
	var iter = ConditionSplit.init(condition, '|');
	
	while (iter.next()) |slice| {
		const parse_result = if (slice[0] == '(') parse(slice[1..], macros)
			else parseAnd(slice, macros);
		result = result or parse_result;
	}
	return result;
}

fn parseAnd(condition: []const u8, macros: *const StringHashMap([]const u8)) bool {
	var result = true;
	var iter = ConditionSplit.init(condition, '&');

	while (iter.next()) |slice| {
		const parse_result = if (slice[0] == '(') parse(slice[1..], macros)
			else parseCmp(slice, macros);
		result = result and parse_result;
	}
	return result;
}

fn parseCmp(condition: []const u8, macros: *const StringHashMap([]const u8)) bool {
	for (0..condition.len) |i| {
		switch (condition[i]) {
			'>' => {
				const lhs = parseU32(termValue(condition[0..i], macros)) catch 1;

				if (condition[i + 1] == '=') {
					const rhs = parseU32(termValue(condition[i + 2..], macros)) catch 1;
					return lhs >= rhs;
				}
				const rhs = parseU32(termValue(condition[i + 1..], macros)) catch 1;
				return lhs > rhs;
			},
			'<' => {
				const lhs = parseU32(termValue(condition[0..i], macros)) catch 1;

				if (condition[i + 1] == '=') {
					const rhs = parseU32(termValue(condition[i + 2..], macros)) catch 1;
					return lhs <= rhs;
				}
				const rhs = parseU32(termValue(condition[i + 1..], macros)) catch 1;
				return lhs < rhs;
			},
			'=' => {
				const lhs = parseU32(termValue(condition[0..i], macros)) catch 1;
				const rhs = parseU32(termValue(condition[i + 1..], macros)) catch 1;
				return lhs == rhs;
			},
			'!' => {
				const lhs = parseU32(termValue(condition[0..i], macros)) catch 1;
				const rhs = parseU32(termValue(condition[i + 2..], macros)) catch 1;
				return lhs != rhs;
			},
			else => continue
		}
	}
	const value = termValue(condition, macros);
	const numeric_value = parseU32(value) catch 1;
	return numeric_value > 0;
}

fn termValue(term: []const u8, macros: *const StringHashMap([]const u8)) []const u8 {
	const trim_nots = std.mem.trimStart(u8, term, "!");
	const negate: bool = (term.len - trim_nots.len) & 1 == 1;

	const trimmed = std.mem.trim(u8, trim_nots, " \t");

	const tmp_result = if (isNumber(trimmed)) trimmed
		else macros.get(trimmed) orelse "0";
	if (!negate) return tmp_result;

	const literal_value = parseU32(trimmed) catch {
		const macro_value = macros.get(trimmed) orelse return "";
		const macro_literal_value = parseU32(macro_value) catch
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
fn isNumber(buf: []const u8) bool {
	for (buf) |c| switch (c) {
		'0'...'9', '_' => continue,
		else => return false
	};
	return true;
}

/// Return an error if `buf` couldn't be parsed into a i32.
/// `input` and `linenr` are just information about the string's position
/// for a more helpful error message.
fn checkOverflow(buf: []const u8, input: []const u8, linenr: usize) !void {
	_ = parseU32(buf) catch {
		log.err(
			"{s}, line {d}: " ++
			"The absolute value of {s} is too big to represent!\n",
			.{input, linenr, buf}
		);
		return E;
	};
}

fn parseU32(buf: []const u8) !u32 {
	return try std.fmt.parseInt(u32, buf, 10);
}
