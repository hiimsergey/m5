const std = @import("std");
const log = @import("log.zig");

const Context = @import("Context.zig");

const MacroInt = Context.MacroInt;
const MacroMap = Context.MacroMap;

const ConditionIterator = struct {
	expression: []const u8,
	token: u8,

	pub fn init(expression: []const u8, token: u8) ConditionIterator {
		return .{ .expression = expression, .token = token };
	}

	pub fn next(self: *ConditionIterator) ?[]const u8 {
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

	fn endBracket(self: *ConditionIterator) []const u8 {
		var scope: usize = 1;
		for (1..self.expression.len) |i| switch (self.expression[i]) {
			'(' => scope += 1,
			')' => {
				scope -= 1;
				if (scope != 0) continue;

				const result = self.expression[0..i];
				self.expression = self.expression[i + 1..];
				return result;
			},
			else => continue
		};
		unreachable;
	}
};

/// State variant describing the current location in character-by-character expression
/// parsing
const ParseState = enum(u8) {
	in_expression,
	in_number,
	expecting_expression,
	expecting_operator
};

// TODO CONSIDER MOVE validate out, so that the other functions dont use linenr
pub fn parse(
	expression: []const u8,
	linenr: usize,
	macros: *const MacroMap
) error{Generic}!bool {
	try validate(expression, linenr);
	return parseOr(expression, macros);
}

fn parseOr(condition: []const u8, macros: *const MacroMap) bool {
	var result = false;
	
	var iter = ConditionIterator.init(condition, '|');
	while (iter.next()) |slice| {
		// TODO CONSIDER use endBracket somewhere
		const parse_result = if (slice[0] == '(') parseOr(slice[1..], macros)
			else parseAnd(slice, macros);
		result = result or parse_result;
	}
	return result;
}

fn parseAnd(condition: []const u8, macros: *const MacroMap) bool {
	var result = true;
	var iter = ConditionIterator.init(condition, '&');

	while (iter.next()) |slice| {
		// TODO CONSIDER use endBracket somewhere
		const parse_result = if (slice[0] == '(') parseOr(slice[1..], macros)
			else parseCmp(slice, macros);
		result = result and parse_result;
	}
	return result;
}

// TODO NOW NOW PLAN
// remove these compiler errors
// finish other features:
//     ???
//     after handling
//     math expressions
// optimize bool expression and other algorithms
fn parseCmp(condition: []const u8, macros: *const MacroMap) bool {
	for (0..condition.len) |i| {
		switch (condition[i]) {
			'>' => {
				const lhs = termValue(condition[0..i], macros);

				if (condition[i + 1] == '=') {
					const rhs = termValue(condition[i + 2..], macros);
					return lhs >= rhs;
				}
				const rhs = termValue(condition[i + 1..], macros);
				return lhs > rhs;
			},
			'<' => {
				const lhs = termValue(condition[0..i], macros);

				if (condition[i + 1] == '=') {
					const rhs = termValue(condition[i + 2..], macros);
					return lhs <= rhs;
				}
				const rhs = termValue(condition[i + 1..], macros);
				return lhs < rhs;
			},
			'=' => {
				const lhs = termValue(condition[0..i], macros);
				const rhs = termValue(condition[i + 1..], macros);
				return lhs == rhs;
			},
			'!' => {
				const lhs = termValue(condition[0..i], macros);
				const rhs = termValue(condition[i + 2..], macros);
				return lhs != rhs;
			},
			else => continue
		}
	}
	const value = termValue(condition, macros);
	return value > 0;
}

// TODO CONSIDER returning u32s already
fn termValue(term: []const u8, macros: *const MacroMap) MacroInt {
	const trim_nots = std.mem.trimStart(u8, term, "!");
	const negate: bool = (term.len - trim_nots.len) & 1 == 1;

	const trimmed = std.mem.trim(u8, trim_nots, " \t");

	// TODO RENAME here
	const trimmed_number = std.fmt.parseInt(MacroInt, trimmed, 10) catch
		return macros.get(trimmed) orelse 0;

	if (!negate) return trimmed_number;
	return @intFromBool(trimmed_number == 0);
}

/// Return whether given string could be successfully parsed into a number.
/// Ignores underscore characters, just like `std.fmt.parseInt` does.
fn isNumber(buf: []const u8) bool {
	for (buf) |c| switch (c) {
		'0'...'9', '_' => continue,
		else => return false
	};
	return true;
}

// TODO FINAL CONSIDER replacing all this with controlled checks in the ConditionIterator
/// Checks `expression` on syntactical validity.
/// Logs on error.
fn validate(expression: []const u8, linenr: usize) error{Generic}!void {
	var scope: usize = 0;
	var state = ParseState.expecting_expression;
	var cur_num_literal: []const u8 = "";

	var i: usize = 0; // We define it outside the loop so we can skip characters.
	while (i < expression.len) : (i += 1) switch (expression[i]) {
		' ', '\t' => switch (state) {
			.in_expression => state = .expecting_operator,
			.in_number => {
				state = .expecting_operator;

				// TODO FINAL TEST
				try validateNumber(cur_num_literal[0..i], linenr);
				cur_num_literal = "";
			},
			else => continue
		},
		'(' => switch (state) {
			.expecting_expression => scope += 1,
			else => {
				log.errWithLineNr(linenr, "Expected expression, got '('!", .{});
				return error.Generic;
			}
		},
		')' => {
			//if (scope == 0 or (state != .in_expression and state != .in_number)) {
			if (scope == 0) {
				log.errWithLineNr(linenr, "Unexpected ')' without opening bracket!", .{});
				return error.Generic;
			}
			switch (state) {
				.expecting_expression => {
					log.errWithLineNr(linenr, "Expected expression, got ')'!", .{});
					return error.Generic;
				},
				.in_number => {
					try validateNumber(cur_num_literal, linenr);
					cur_num_literal = "";
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
				log.errWithLineNr(linenr, "Invalid character '-'!", .{});
				return error.Generic;
			}
		},
		'0'...'9' => switch (state) {
			.in_expression => continue,
			.in_number => cur_num_literal.len += 1,
			.expecting_expression => {
				state = .in_number;
				cur_num_literal = expression[i..];
			},
			.expecting_operator => {
				log.errWithLineNr(linenr, "Expected operator, got number!", .{});
				return error.Generic;
			}
		},
		'_' => switch (state) {
			.in_expression => continue,
			.in_number => cur_num_literal.len += 1,
			.expecting_expression => state = .in_expression,
			.expecting_operator => {
				log.errWithLineNr(linenr, "Expected operator, got '_'!", .{});
				return error.Generic;
			}
			// TODO ADD test leading and trailing underscore in numbers
		},
		'&', '|', '=' => switch (state) {
			.expecting_expression => {
				log.errWithLineNr(linenr,
					"Expected expression, got operator '{c}'!",
					.{expression[i]});
				return error.Generic;
			},
			else => state = .expecting_expression
		},
		'<', '>' => {
			switch (state) {
				.expecting_expression => {
					log.errWithLineNr(linenr,
						"Expected expression, got comparison operator '{c}'!",
						.{expression[i]});
					return error.Generic;
				},
				else => state = .expecting_expression
			}
			if (i < expression.len - 1 and expression[i + 1] == '=') i += 1;
		},
		'!' => switch (state) {
			.expecting_expression => continue,
			.expecting_operator => {
				if (i < expression.len - 1 and expression[i + 1] != '=') {
					log.errWithLineNr(linenr, "Expected operator, got '!'!", .{});
					return error.Generic;
				}
				i += 1;
				state = .expecting_expression;
			},
			else => {
				log.errWithLineNr(linenr, "Unexpected '!' in number!", .{});
				return error.Generic;
			},
		},
		else => switch (state) {
			.in_expression => continue,
			.in_number => {
				log.errWithLineNr(linenr,
					"Unexpected character '{c}' in number!",
					.{expression[i]});
				return error.Generic;
			},
			.expecting_expression => state = .in_expression,
			.expecting_operator => {
				log.errWithLineNr(linenr,
					"Expected operator, got '{c}'!",
					.{expression[i]});
				return error.Generic;
			}
		},
	};

	if (scope > 0) {
		log.errWithLineNr(linenr, "Unclosed parenthesis!", .{});
		return error.Generic;
	}
	// TODO if .in_number, then check overflow again
	if (state == .expecting_expression) {
		log.errWithLineNr(linenr, "Expected expression at the end!", .{});
		return error.Generic;
	}
}

/// Checks `buf` on whether it represents a an unsigned 32-bit integer.
/// Logs on error.
fn validateNumber(buf: []const u8, linenr: usize) error{Generic}!void {
	_ = std.fmt.parseInt(u32, buf, 10) catch |e| {
		switch (e) {
			error.Overflow => log.errWithLineNr(linenr,
				"Absolute value of '{s}' is too big to represent!",
				.{buf}),
			error.InvalidCharacter => log.errWithLineNr(linenr,
				"Value '{s}' is not a valid number!", .{buf})
		}
		return error.Generic;
	};
}
