const std = @import("std");
const log = @import("log.zig");

const Context = @import("Context.zig");
const MacroInt = Context.MacroInt;

const ConditionIterator = struct {
	expression: []const u8,
	token: u8,

	pub fn init(expression: []const u8, token: u8) ConditionIterator {
		return .{ .expression = expression, .token = token };
	}

	/// Does not log.
	pub fn next(self: *ConditionIterator) error{User}!?[]const u8 {
		if (self.expression.len == 0) return null;
		// TODO REPLACE with Context.trimWStart
		self.expression = std.mem.trimStart(u8, self.expression, " ");

		if (self.expression[0] == '(') return try self.endBracket();

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

	// TODO this function should errhandle the condition
	/// Called when first character in buffer is opening parenthesis.
	/// Returns slice ending with its corresponding closing parenthesis and advances
	/// iterator.
	/// If there is no closing parenthesis, returns `error.User`.
	/// Does not log.
	fn endBracket(self: *ConditionIterator) error{User}![]const u8 {
		var scope: usize = 1;
		for (1..self.expression.len) |i| switch (self.expression[i]) {
			'(' => scope += 1,
			')' => {
				scope -= 1;
				if (scope != 0) continue;

				const result = self.expression[1..i];
				self.expression = self.expression[i + 1..];
				return result;
			},
			else => continue
		};
		return error.User;
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

// TODO CONSIDER only logging here and introducing a custom error type for other parse functions
// TODO CONSIDER MOVE validate out, so that the other functions dont use linenr
pub fn parse(
	expression: []const u8,
	linenr: usize,
	ctx: *const Context
) error{User}!bool {
	try validate(expression, linenr);

	var result = false;
	
	var it = ConditionIterator.init(expression, '|');
	while (it.next() catch {
		log.errWithLineNr(linenr, "Unclosed parenthesis!", .{});
		return error.User;
	}) |slice| {
		// TODO CONSIDER use endBracket somewhere
		const parse_result = if (slice[0] == '(') try parse(slice[1..], linenr, ctx)
			else try parseAnd(slice, linenr, ctx);
		result = result or parse_result;
	}
	return result;
}

fn parseAnd(condition: []const u8, linenr: usize, ctx: *const Context) error{User}!bool {
	var result = true;
	var it = ConditionIterator.init(condition, '&');

	while (it.next() catch {
		log.errWithLineNr(linenr, "Unclosed parenthesis!", .{});
		return error.User;
	}) |slice| {
		// TODO CONSIDER use endBracket somewhere
		const parse_result = if (slice[0] == '(') try parse(slice[1..], linenr, ctx)
			else try parseCmp(slice, linenr, ctx);
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
fn parseCmp(condition: []const u8, linenr: usize, ctx: *const Context) error{User}!bool {
	for (0..condition.len) |i| {
		switch (condition[i]) {
			'>' => {
				const lhs = try termValue(condition[0..i], linenr, ctx);

				if (condition[i + 1] == '=') {
					const rhs = try termValue(condition[i + 2..], linenr, ctx);
					return lhs >= rhs;
				}
				const rhs = try termValue(condition[i + 1..], linenr, ctx);
				return lhs > rhs;
			},
			'<' => {
				const lhs = try termValue(condition[0..i], linenr, ctx);

				if (condition[i + 1] == '=') {
					const rhs = try termValue(condition[i + 2..], linenr, ctx);
					return lhs <= rhs;
				}
				const rhs = try termValue(condition[i + 1..], linenr, ctx);
				return lhs < rhs;
			},
			'=' => {
				const lhs = try termValue(condition[0..i], linenr, ctx);
				const rhs = try termValue(condition[i + 1..], linenr, ctx);
				return lhs == rhs;
			},
			'!' => {
				// foo != bar
				if (condition[i + 1] == '=') {
					const lhs = try termValue(condition[0..i], linenr, ctx);
					const rhs = try termValue(condition[i + 2..], linenr, ctx);
					return lhs != rhs;
				}
				// !foo
				break;
			},
			else => continue
		}
	}

	const value: MacroInt = try termValue(condition, linenr, ctx);
	return value > 0;
}

// TODO implement mathematical expressions
/// Logs on error.
fn termValue(
	term: []const u8,
	linenr: usize,
	ctx: *const Context
) error{User}!MacroInt {
	const trim_nots = std.mem.trimStart(u8, term, "!");
	const negate: bool = (term.len - trim_nots.len) & 1 == 1;
	const literal = std.mem.trim(u8, trim_nots, " \t");

	const value: MacroInt = std.fmt.parseInt(MacroInt, literal, 10) catch |e| value: {
		if (e == error.Overflow) {
			log.errWithLineNr(linenr,
				\\Number {s} is not representable!"
				\\Only numbers from {d} to {d} are supported!
				, .{literal, std.math.minInt(MacroInt), std.math.maxInt(MacroInt)});
			return error.User;
		}

		try validateLiteral(literal, linenr);

		break :value ctx.macros.get(literal) orelse {
			if (!ctx.flags.safe) break :value 0;

			// TODO TEST correct flushing
			log.errWithLineNr(linenr,
				"Macro '{s}' is undefined! (error shown because of --safe)",
				.{literal}
			);
			// TODO CHECK that this leads to proper shutdown
			return error.User;
		};
	};

	if (!negate) return value;
	return @intFromBool(value == 0);
}

fn parseDivide(expr: []const u8, linenr: usize, ctx: *const Context) error{User}!bool {
	var it = ConditionIterator.init(expr, '/');

	var result: MacroInt = result: {
		const maybe = it.next() catch {
			log.errWithLineNr(linenr, "Unclosed parenthesis!", .{});
			return error.User;
		};
		break :result maybe.?;
	};

	while (it.next() catch {
		log.errWithLineNr(linenr, "Unclosed parenthesis!", .{});
		return error.User;
	}) |slice| {
		// TODO CONSIDER use endBracket somewhere
		const parse_result = if (slice[0] == '(') try parse(slice[1..], linenr, ctx)
			else try parseMult(slice, linenr, ctx);
		result = @divFloor(result, parse_result);
	}
	return result;
}

fn parseMult(expr: []const u8, linenr: usize, ctx: *const Context) error{User}!bool {
	var it = ConditionIterator.init(expr, '*');

	var result: MacroInt = result: {
		const maybe = it.next() catch {
			log.errWithLineNr(linenr, "Unclosed parenthesis!", .{});
			return error.User;
		};
		break :result maybe.?;
	};

	while (it.next() catch {
		log.errWithLineNr(linenr, "Unclosed parenthesis!", .{});
		return error.User;
	}) |slice| {
		// TODO CONSIDER use endBracket somewhere
		const parse_result = if (slice[0] == '(') try parse(slice[1..], linenr, ctx)
			else try parseMult(slice, linenr, ctx);
		result = @divFloor(result, parse_result);
	}
	return result;
}

// TODO FINAL REMOVE
fn validate(expression: []const u8, linenr: usize) error{User}!void {
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
				return error.User;
			}
		},
		')' => {
			//if (scope == 0 or (state != .in_expression and state != .in_number)) {
			if (scope == 0) {
				log.errWithLineNr(linenr, "Unexpected ')' without opening bracket!", .{});
				return error.User;
			}
			switch (state) {
				.expecting_expression => {
					log.errWithLineNr(linenr, "Expected expression, got ')'!", .{});
					return error.User;
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
				return error.User;
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
				return error.User;
			}
		},
		'_' => switch (state) {
			.in_expression => continue,
			.in_number => cur_num_literal.len += 1,
			.expecting_expression => state = .in_expression,
			.expecting_operator => {
				log.errWithLineNr(linenr, "Expected operator, got '_'!", .{});
				return error.User;
			}
			// TODO ADD test leading and trailing underscore in numbers
		},
		'&', '|', '=' => switch (state) {
			.expecting_expression => {
				log.errWithLineNr(linenr,
					"Expected expression, got operator '{c}'!",
					.{expression[i]});
				return error.User;
			},
			else => state = .expecting_expression
		},
		'<', '>' => {
			switch (state) {
				.expecting_expression => {
					log.errWithLineNr(linenr,
						"Expected expression, got comparison operator '{c}'!",
						.{expression[i]});
					return error.User;
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
					return error.User;
				}
				i += 1;
				state = .expecting_expression;
			},
			else => {
				log.errWithLineNr(linenr, "Unexpected '!' in number!", .{});
				return error.User;
			},
		},
		else => switch (state) {
			.in_expression => continue,
			.in_number => {
				log.errWithLineNr(linenr,
					"Unexpected character '{c}' in number!",
					.{expression[i]});
				return error.User;
			},
			.expecting_expression => state = .in_expression,
			.expecting_operator => {
				log.errWithLineNr(linenr,
					"Expected operator, got '{s}'!",
					.{expression[i..]});
				return error.User;
			}
		},
	};

	if (scope > 0) {
		log.errWithLineNr(linenr, "Unclosed parenthesis!", .{});
		return error.User;
	}
	// TODO if .in_number, then check overflow again
	if (state == .expecting_expression) {
		log.errWithLineNr(linenr, "Expected expression at the end!", .{});
		return error.User;
	}
}

/// Returns an error and logs if iterator item contains syntax error.
/// Logs on error.
fn validateLiteral(buf: []const u8, linenr: usize) error{User}!void {
	if (buf.len == 0) {
		log.err("Expected expression!", .{});
		return error.User;
	}
	for (buf) |c| switch (c) {
		' ' => {
			log.errWithLineNr(linenr, "Syntax error!", .{});
			return error.User;
		},
		'(' => {
			log.errWithLineNr(linenr, "Expected operator, got '('!", .{});
			return error.User;
		},
		')' => {
			log.errWithLineNr(linenr, "Expected expression, got ')'!", .{});
			return error.User;
		},
		else => continue
	};
}

// TODO REMOVE
/// Checks `buf` on whether it represents a an unsigned 32-bit integer.
/// Logs on error.
fn validateNumber(buf: []const u8, linenr: usize) error{User}!void {
	_ = std.fmt.parseInt(MacroInt, buf, 10) catch |e| {
		switch (e) {
			// TODO add "only X to Y" comment
			error.Overflow => log.errWithLineNr(linenr,
				\\Number {s} is not representable!"
				\\Only numbers from {d} to {d} are supported!
				, .{buf, std.math.minInt(MacroInt), std.math.maxInt(MacroInt)}),
			error.InvalidCharacter => log.errWithLineNr(linenr,
				"Value '{s}' is not a valid number!", .{buf})
		}
		return error.User;
	};
}

// TODO ADD test for \t characters
// TODO ADD test for too much whitespace
// TODO ADD test for mixed whitespace
// TODO TEST these scenarios are errhandled:
//   "Expected expression, got '('!", .{});
//   "Unexpected ')' without opening bracket!", .{});
//   "Expected expression, got ')'!", .{});
//   "Invalid character '-'!", .{});
//   "Expected operator, got number!", .{});
//   "Expected operator, got '_'!", .{});
//   "Expected expression, got operator '{c}'!",
//   "Expected expression, got comparison operator '{c}'!",
//   "Expected operator, got '!'!", .{});
//   "Unexpected '!' in number!", .{});
//   "Unexpected character '{c}' in number!",
//   "Expected operator, got '{s}'!",
//   "Unclosed parenthesis!", .{});
//   "Expected expression at the end!", .{});
// TODO FINAL CHECK is AND weaker than OR?
