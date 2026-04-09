const std = @import("std");
const log = @import("log.zig");

const CompareOperator = std.math.CompareOperator;
const Context = @import("Context.zig");
const MacroInt = Context.MacroInt;

const ParseIterator = struct {
	expr: []const u8,
	tokens: []const u8,

	pub fn init(condition: []const u8, tokens: []const u8) ParseIterator {
		return .{ .expr = condition, .tokens = tokens };
	}

	/// If not null, returns next item in the iterator, respecting parentheses and matched
	/// token.
	/// Returns null if `self.condition` was iterated through completely.
	/// Does not log.
	pub fn next(self: *ParseIterator) error{UnclosedParenthesis}!?struct{[]const u8, u8} {
		if (self.expr.len == 0) return null;
		// TODO ALL REPLACE with Context.trimWStart
		self.expr = std.mem.trimStart(u8, self.expr, " \t");

		var i: usize = 0;
		while (i < self.expr.len) : (i += 1) {
			if (self.expr[0] == '(') {
				_ = try self.endBracket();
				i = 0;
				continue;
			}
			if (std.mem.containsAtLeastScalar(u8, self.tokens, 1, self.expr[i])) {
				defer self.expr = self.expr[i + 1..];
				return .{self.expr[0..i], self.expr[i]};
			}
		}

		// In the case that we're returning the whole remaining string, we will not need
		// the token, therefore we use 0 as a "Don't-care".
		defer self.expr = "";
		return .{self.expr, 0};
	}

	// TODO this function should errhandle the condition
	/// Called when first character in buffer is opening parenthesis.
	/// Returns slice ending with its corresponding closing parenthesis and advances
	/// iterator.
	/// If there is no closing parenthesis, returns `error.User`.
	/// Does not log.
	fn endBracket(self: *ParseIterator) error{UnclosedParenthesis}![]const u8 {
		var scope: usize = 1;
		for (1..self.expr.len) |i| switch (self.expr[i]) {
			'(' => scope += 1,
			')' => {
				scope -= 1;
				if (scope != 0) continue;

				defer self.expr = self.expr[i + 1..];
				return self.expr[0..i + 1];
			},
			else => continue
		};
		return ParseError.UnclosedParenthesis;
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

// TODO CONSIDER MOVE
const ParseError = error{
	DoubleEquals,
	EmptyLiteral,
	UnclosedParenthesis,
	UndefinedMacro,
	UnexpectedBang,
	UnexpectedBangOperator,
	UnexpectedLparen,
	UnexpectedRparen,
	UnexpectedSpace,
	UnrepresentableNumber
};

/// Logs on error.
pub fn parse(expr: []const u8, linenr: usize, ctx: *const Context) error{User}!bool {
	std.debug.print("parsing '{s}'\n", .{expr});
	return parseOr(expr, ctx) catch |e| {
		switch (e) {
			ParseError.DoubleEquals =>
				log.errWithLineNr(linenr, "Don't use '=='! Use '=' instead!", .{}),
			ParseError.UnclosedParenthesis =>
				log.errWithLineNr(linenr, "Unclosed parenthesis!", .{}),
			ParseError.EmptyLiteral =>
				log.errWithLineNr(linenr,
					"Expected expression, found empty literal!", .{}),
			ParseError.UndefinedMacro =>
				log.errWithLineNr(linenr,
					"Undefined macro found! (You see this error because of --safe)", .{}),
			ParseError.UnexpectedBang =>
				log.errWithLineNr(linenr, "Unexpected '!' Perhaps you meant '!='?", .{}),
			ParseError.UnexpectedLparen =>
				log.errWithLineNr(linenr, "Expected operator, found '('!", .{}),
			ParseError.UnexpectedRparen =>
				log.errWithLineNr(linenr, "Expected expression, found ')'!", .{}),
			ParseError.UnexpectedSpace =>
				log.errWithLineNr(linenr, "Invalid spacing!", .{}),
			ParseError.UnrepresentableNumber =>
				log.errWithLineNr(linenr,
					\\Unrepresentable number found!
					\\Only numbers from {d} to {d} are supported!
					, .{std.math.minInt(MacroInt), std.math.maxInt(MacroInt)})
		}
		return error.User;
	};
}

// TODO CONSIDER only logging here and introducing a custom error type for other parse functions
// TODO CONSIDER ALL exclude linenr from functions
// TODO CONSIDER MOVE validate out, so that the other functions dont use linenr
fn parseOr(expr: []const u8, ctx: *const Context) ParseError!bool {
	std.debug.print("\nparseOr\n", .{});
	var result = false;

	var it = ParseIterator.init(expr, "|");
	while (try it.next()) |tuple| {
		const slice: []const u8 = tuple.@"0";
		std.debug.print("+'{s}'\n", .{slice});
		const parse_result = if (slice[0] == '(') try parseOr(slice[1..], ctx)
			else try parseAnd(slice, ctx);
		result = result or parse_result;
	}
	std.debug.print("\n~parseOr\n", .{});
	return result;
}

fn parseAnd(expr: []const u8, ctx: *const Context) ParseError!bool {
	std.debug.print("\nparseAnd\n", .{});
	var result = true;

	var it = ParseIterator.init(expr, "&");
	while (try it.next()) |tuple| {
		const slice: []const u8 = tuple.@"0";
		std.debug.print("+'{s}'\n", .{slice});
		const parse_result = if (slice[0] == '(') try parseOr(slice[1..], ctx)
			else try parseCmp(slice, ctx);
		result = result and parse_result;
	}
	std.debug.print("\n~parseAnd\n", .{});
	return result;
}

// TODO FINAL document the cmp behavior (like a<b<c)
fn parseCmp(expr: []const u8, ctx: *const Context) ParseError!bool {
	std.debug.print("\nparseCmp\n", .{});
	const correctTuple = struct {
		fn f(it: *ParseIterator, buf: *[]const u8, char: u8)
		error{DoubleEquals, UnexpectedBangOperator}!CompareOperator {
			if (buf.*[buf.len - 1] == '!') switch (char) {
				'<', '>' => return ParseError.UnexpectedBangOperator,
				'=' => {
					buf.* = buf.*[0..buf.len - 1];
					return .neq;
				},
				else => unreachable
			};
			switch (char) {
				'<' => {
					if (it.expr[0] == '=') {
						it.expr = it.expr[1..];
						return .lte;
					}
					return .lt;
				},
				'>' => {
					if (it.expr[0] == '=') {
						it.expr = it.expr[1..];
						return .gte;
					}
					return .gt;
				},
				'=' => {
					if (it.expr[0] == '=') return ParseError.DoubleEquals;
					return .eq;
				},
				else => unreachable
			}
		}
	}.f;

	var it = ParseIterator.init(expr, "<>=");

	const lhs_buf: []const u8, var cmp: CompareOperator = lhs_buf_cmp_char: {
		const lhs_buf: []const u8, const cmp_char: u8 = (try it.next()).?;
		const cmp: CompareOperator = try correctTuple(it, lhs_buf, cmp_char);
		break :lhs_buf_cmp_char .{lhs_buf, cmp};
	};
	std.debug.print("+'{s}'\n", .{lhs_buf});
	var lhs: MacroInt = try termValue(lhs_buf, ctx);

	// TODO NOW NOW
	// just wrap it.next() into what lhs_buf_cmp_char: is doing and just use it in the loop
	// but you have to introduce the next_cmp variable
	while (try it.next()) |tuple| {
		const slice: []const u8 = tuple.@"0";
		const rhs: MacroInt = parse_result: {
			if (slice[0] == '(') {
				const rhs_bool: bool = try parseOr(slice[1..], ctx);
				break :parse_result @intFromBool(rhs_bool);
			}
			break :parse_result try termValue(slice, ctx);
		};
		switch (cmp) {
			.lt => if (lhs >= rhs) return false,
			.lte => if (lhs > rhs) return false,
			.eq => if (lhs != rhs) return false,
			.gt => if (lhs <= rhs) return false,
			.gte => if (lhs < rhs) return false,
			.neq => if (lhs == rhs) return false,
		}

		lhs = rhs;
		cmp = try getOperator(&it, tuple.@"1");
	}

	std.debug.print("\n~parseCmp\n", .{});
	return true;
}

// TODO REMOVE
// remove these compiler errors
// optimize bool expression and other algorithms
fn parseCmp0(expr: []const u8, ctx: *const Context) ParseError!bool {
	for (0..expr.len) |i| {
		switch (expr[i]) {
			'>' => {
				const lhs = try termValue(expr[0..i], ctx);

				if (expr[i + 1] == '=') {
					const rhs = try termValue(expr[i + 2..], ctx);
					return lhs >= rhs;
				}
				const rhs = try termValue(expr[i + 1..], ctx);
				return lhs > rhs;
			},
			'<' => {
				const lhs = try termValue(expr[0..i], ctx);

				if (expr[i + 1] == '=') {
					const rhs = try termValue(expr[i + 2..], ctx);
					return lhs <= rhs;
				}
				const rhs = try termValue(expr[i + 1..], ctx);
				return lhs < rhs;
			},
			'=' => {
				const lhs = try termValue(expr[0..i], ctx);
				const rhs = try termValue(expr[i + 1..], ctx);
				return lhs == rhs;
			},
			'!' => {
				// foo != bar
				if (expr[i + 1] == '=') {
					const lhs = try termValue(expr[0..i], ctx);
					const rhs = try termValue(expr[i + 2..], ctx);
					return lhs != rhs;
				}
				// !foo
				break;
			},
			else => continue
		}
	}

	const value: MacroInt = try termValue(expr, ctx);
	return value != 0;
}

// TODO implement mathematical expressions
/// Logs on error.
fn termValue(term: []const u8, ctx: *const Context) error{
	EmptyLiteral,
	UndefinedMacro,
	UnexpectedLparen,
	UnexpectedRparen,
	UnexpectedSpace,
	UnrepresentableNumber
}!MacroInt {
	// TODO NOW CONSIDER check for illegal characters
	// there's a reason not to, cause maybe validateKey used to do the job at the
	// start

	const trim_nots = std.mem.trimStart(u8, term, "!");
	const negate: bool = (term.len - trim_nots.len) & 1 == 1;
	const literal = std.mem.trim(u8, trim_nots, " \t");

	const value: MacroInt = std.fmt.parseInt(MacroInt, literal, 10) catch |e| value: {
		if (e == error.Overflow) return ParseError.UnrepresentableNumber;
		try validateLiteral(literal);

		break :value ctx.macros.get(literal) orelse {
			if (!ctx.flags.safe) break :value 0;
			return error.UndefinedMacro;
		};
	};

	if (!negate) return value;
	return @intFromBool(value == 0);
}

/// Returns an error and logs if iterator item contains syntax error.
/// Logs on error.
fn validateLiteral(buf: []const u8)
error{EmptyLiteral, UnexpectedSpace, UnexpectedLparen, UnexpectedRparen}!void {
	if (buf.len == 0) return ParseError.EmptyLiteral;
	for (buf) |c| switch (c) {
		' ' => return ParseError.UnexpectedSpace,
		'(' => return ParseError.UnexpectedLparen,
		')' => return ParseError.UnexpectedRparen,
		else => continue
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
