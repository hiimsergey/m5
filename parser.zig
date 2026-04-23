const std = @import("std");
const a = @import("alias.zig");
const log = @import("log.zig");

const CompareOperator = std.math.CompareOperator;
const Context = @import("Context.zig");
const MacroInt = Context.MacroInt;

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const gpa = std.testing.allocator;

const NextAdjustedError = error{
	DoubleEquals,
	UnclosedParenthesis,
	UnexpectedBangOperator,
	UnexpectedOperator
};
const ValidateLiteralError = error{
	EmptyLiteral,
	UnexpectedExpression,
	UnexpectedRparen
};
const TermValueError = error{
	UndefinedMacro,
	UnrepresentableNumber
} || ValidateLiteralError;
const ParseError = NextAdjustedError || TermValueError;

const ParseIterator = struct {
	expr: []const u8,
	tokens: []const u8,

	pub fn init(condition: []const u8, tokens: []const u8) ParseIterator {
		return .{ .expr = condition, .tokens = tokens };
	}

	/// If not null, returns next item in the iterator, respecting parentheses and matched
	/// token.
	/// Returns null if `self.condition` was iterated through completely.
	/// Returns error.UnclosedParenthesis if expression contains unclosed opening
	/// parenthesis.
	/// Does not log.
	pub fn next(self: *ParseIterator) error{UnclosedParenthesis}!?struct {[]const u8, u8} {
		if (self.expr.len == 0) return null;
		self.expr = a.trimWStart(self.expr);

		var i: usize = 0;
		while (i < self.expr.len) : (i += 1) {
			if (self.expr[i] == '(') {
				_ = try self.closeParen(&i);
				continue;
			}
			if (std.mem.containsAtLeastScalar(u8, self.tokens, 1, self.expr[i])) {
				defer self.expr = self.expr[i + 1..];
				return .{self.expr[0..i], self.expr[i]};
			}
		}

		// In the case that we're returning the whole remaining string, we will not need
		// the token, therefore we use 0 as a dontcare.
		defer self.expr = "";
		return .{self.expr, 0};
	}

	// TODO this function should errhandle the condition
	/// Called when first character in buffer is opening parenthesis.
	/// Returns slice ending with its corresponding closing parenthesis and advances
	/// iterator.
	/// If there is no closing parenthesis, returns `error.UnclosedParenthesis`.
	/// Does not log.
	fn closeParen(self: *ParseIterator, i: *usize) error{UnclosedParenthesis}!void {
		i.* += 1;
		var scope: usize = 1;
		while (i.* < self.expr.len) : (i.* += 1) switch (self.expr[i.*]) {
			'(' => scope += 1,
			')' => {
				scope -= 1;
				if (scope == 0) return;
			},
			else => continue
		};
		return error.UnclosedParenthesis;
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

/// Logs on error.
pub fn parse(expr: []const u8, linenr: usize, ctx: *const Context) ParseError!bool {
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
			ParseError.UnexpectedBangOperator =>
				log.errWithLineNr(linenr, "Unexpected operator after '!'", .{}),
			ParseError.UnexpectedLparen =>
				log.errWithLineNr(linenr, "Expected operator, found '('!", .{}),
			ParseError.UnexpectedOperator =>
				log.errWithLineNr(linenr, "Expected expression, found operator!", .{}),
			ParseError.UnexpectedRparen =>
				log.errWithLineNr(linenr, "Expected expression, found ')'!", .{}),
			ParseError.UnrepresentableNumber =>
				log.errWithLineNr(linenr,
					\\Unrepresentable number found!
					\\Only numbers from {d} to {d} are supported!
					, .{std.math.minInt(MacroInt), std.math.maxInt(MacroInt)})
		}
		return e;
	};
}

test parse {
	// TODO ok-cases
	var ctx = Context.init(gpa);
	defer ctx.deinit();

	try expectEqual(false, parse("a", 1, &ctx));

	const DoubleEquals = ParseError.DoubleEquals;
	try expectError(DoubleEquals, parse("a == b", 1, &ctx));
	try expectError(DoubleEquals, parse("a==b", 1, &ctx));
	try expectError(DoubleEquals, parse("a ==b", 1, &ctx));
	try expectError(DoubleEquals, parse("a== b", 1, &ctx));
	try expectError(DoubleEquals, parse("a   ==       b", 1, &ctx));
	// TODO NOW DEBUG
	try expectError(DoubleEquals, parse("(a | b) == (c & d | (e + f))", 1, &ctx));
}

fn parseOr(expr: []const u8, ctx: *const Context) ParseError!bool {
	var result = false;

	var it = ParseIterator.init(expr, "|");
	while (try it.next()) |tuple| {
		const slice: []const u8 = tuple.@"0";
		const parse_result = if (slice[0] == '(') try parseOr(slice[1..], ctx)
			else try parseAnd(slice, ctx);
		result = result or parse_result;
	}
	return result;
}

fn parseAnd(expr: []const u8, ctx: *const Context) ParseError!bool {
	var result = true;

	var it = ParseIterator.init(expr, "&");
	while (try it.next()) |tuple| {
		const slice: []const u8 = tuple.@"0";
		const parse_result = if (slice[0] == '(') try parseOr(slice[1..], ctx)
			else try parseCmp(slice, ctx);
		result = result and parse_result;
	}
	return result;
}

// TODO FINAL document the cmp behavior (like a<b<c)
fn parseCmp(expr: []const u8, ctx: *const Context) ParseError!bool {
	const nextAdjusted = struct {
		fn f(it: *ParseIterator)
		NextAdjustedError!struct {[]const u8, ?CompareOperator} {
			var buf: []const u8, const char: u8 = (try it.next()).?;
			if (buf.len == 0) return NextAdjustedError.UnexpectedOperator;
			if (char == 0) return .{buf, null};

			if (buf[buf.len - 1] == '!') switch (char) {
				'<', '>' => return NextAdjustedError.UnexpectedBangOperator,
				'=' => {
					buf = buf[0..buf.len - 1];
					return .{buf, .neq};
				},
				else => unreachable
			};
			switch (char) {
				'<' => {
					if (it.expr[0] == '=') {
						it.expr = it.expr[1..];
						return .{buf, .lte};
					}
					return .{buf, .lt};
				},
				'>' => {
					if (it.expr[0] == '=') {
						it.expr = it.expr[1..];
						return .{buf, .gte};
					}
					return .{buf, .gt};
				},
				'=' => {
					if (it.expr[0] == '=') return NextAdjustedError.DoubleEquals;
					return .{buf, .eq};
				},
				else => unreachable
			}
		}
	}.f;

	var it = ParseIterator.init(expr, "<>=");

	const lhs_buf: []const u8, const maybe_cmp: ?CompareOperator = try nextAdjusted(&it);
	var lhs: MacroInt = lhs: {
		if (lhs_buf[0] == '(') {
			const lhs: bool = try parseOr(expr[1..], ctx);
			break :lhs @intFromBool(lhs);
		}
		break :lhs try termValue(lhs_buf, ctx);
	};
	var cmp: CompareOperator = maybe_cmp orelse return lhs > 0;

	while (true) {
		const slice: []const u8, const new_cmp: ?CompareOperator = try nextAdjusted(&it);
		const rhs: MacroInt = rhs: {
			if (slice[0] == '(') {
				const rhs_bool: bool = try parseOr(slice[1..], ctx);
				break :rhs @intFromBool(rhs_bool);
			}
			break :rhs try termValue(slice, ctx);
		};
		switch (cmp) {
			.lt => if (lhs >= rhs) return false,
			.lte => if (lhs > rhs) return false,
			.eq => if (lhs != rhs) return false,
			.gt => if (lhs <= rhs) return false,
			.gte => if (lhs < rhs) return false,
			.neq => if (lhs == rhs) return false,
		}

		cmp = new_cmp orelse break;
		lhs = rhs;
	}

	return true;
}

// TODO implement mathematical expressions
/// Logs on error.
fn termValue(term: []const u8, ctx: *const Context) TermValueError!MacroInt {
	// TODO NOW CONSIDER check for illegal characters
	// there's a reason not to, cause maybe validateKey used to do the job at the
	// start

	const trim_nots = std.mem.trimStart(u8, term, "!");
	const negate: bool = (term.len - trim_nots.len) & 1 == 1;
	const literal = std.mem.trim(u8, trim_nots, " \t");

	const value: MacroInt = std.fmt.parseInt(MacroInt, literal, 10) catch |e| value: {
		if (e == error.Overflow) return TermValueError.UnrepresentableNumber;
		try validateLiteral(literal);

		break :value ctx.macros.get(literal) orelse {
			if (!ctx.safe) break :value 0;
			return TermValueError.UndefinedMacro;
		};
	};

	if (!negate) return value;
	return @intFromBool(value == 0);
}

/// Returns an error and logs if iterator item contains syntax error.
/// Logs on error.
fn validateLiteral(buf: []const u8) ValidateLiteralError!void {
	if (buf.len == 0) return ValidateLiteralError.EmptyLiteral;
	for (buf) |c| switch (c) {
		' ', '(' => return ValidateLiteralError.UnexpectedExpression,
		')' => return ValidateLiteralError.UnexpectedRparen,
		else => continue
	};
}

// TODO TEST
// a & b
// a & a
// a | b
// a | a
// (a)
// a        >          b

// TODO TEST invalid
// a &
// a |
// a <
// & a
// | a
// < a
// == a
// a =
// a = b
// a !
// a != b
// a ! b
// ! a
// (a
// a)
// a (b)
// a (b
// a) b
// a + b
// a +- b
// a &| b
// a & & b

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
