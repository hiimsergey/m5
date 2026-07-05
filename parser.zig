const std = @import("std");
const a = @import("alias.zig");
const log = @import("log.zig");

const CompareOperator = std.math.CompareOperator;
const Context = @import("Context.zig");
const MacroInt = Context.MacroInt;

const gpa = std.testing.allocator;

const NextAdjustedError = error{
	DoubleEquals,
	UnclosedParenthesis,
	UnexpectedBangOperator,
	UnexpectedOperator
};
const ValidateLiteralError = error{
	Empty,
	UnexpectedExpression,
	UnexpectedRparen
};
const TermValueError = error{
	UndefinedMacro,
	UnrepresentableNumber
} || ValidateLiteralError;
const ParseError = NextAdjustedError || TermValueError;

const ParseIterator = struct {
	const Next = struct {
		item: []const u8,
		matched: u8
	};

	expr: []const u8,
	tokens: []const u8,

	pub fn init(condition: []const u8, tokens: []const u8) ParseIterator {
		return .{ .expr = condition, .tokens = tokens };
	}

	/// If not null, returns next item in the iterator, respecting parentheses and matched
	/// token.
	/// Returns null if `self.condition` was iterated through completely.
	/// Returns `error.UnclosedParenthesis` if expression contains unclosed opening
	/// parenthesis.
	/// Does not log.
	pub fn next(self: *ParseIterator) error{UnclosedParenthesis}!?Next {
		if (self.expr.len == 0) return null;
		self.expr = a.trimWStart(self.expr);

		var i: usize = 0;
		while (i < self.expr.len) : (i += 1) {
			if (self.expr[i] == '(') {
				std.debug.print("oops '{s}'\n", .{self.expr});
				i += try findCloseParen(self.expr[i..]);
				continue;
				// // TODO NOW DEBUG this is the part
				// defer self.expr = self.expr[i + 1..];
				// return .{ .item = self.expr[0..i + 1], .matched = 0 };
			}
			if (std.mem.containsAtLeastScalar(u8, self.tokens, 1, self.expr[i])) {
				defer self.expr = self.expr[i + 1..];
				return .{ .item = self.expr[0..i], .matched = self.expr[i] };
			}
		}

		// In the case that we're returning the whole remaining string, we will not need
		// the token and thus return 0 as a decoy value.
		// (?u8 would take up more space, as of now :pensive:)
		defer self.expr = "";
		return .{ .item = self.expr, .matched = 0 };
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

/// Evaluates given expression to either true or false, taking defined variables in `ctx`
/// into consideration.
/// Logs on error.
pub fn parse(expr: []const u8, linenr: usize, ctx: *const Context) ParseError!bool {
	std.debug.assert(expr.len > 0);

	return parseGates(expr, ctx) catch |e| {
		switch (e) {
			ParseError.DoubleEquals =>
				log.errWithLineNr(linenr, "Don't use '=='! Use '=' instead!", .{}),
			ParseError.UnclosedParenthesis =>
				log.errWithLineNr(linenr, "Unclosed parenthesis!", .{}),
			ParseError.Empty =>
				log.errWithLineNr(linenr,
					"Expected expression, found empty literal!", .{}),
			ParseError.UndefinedMacro =>
				log.errWithLineNr(linenr,
					"Undefined macro found! (You see this error because of --safe)", .{}),
			ParseError.UnexpectedBangOperator =>
				log.errWithLineNr(linenr, "Unexpected operator after '!'", .{}),
			ParseError.UnexpectedExpression =>
				log.errWithLineNr(linenr, "Expected operator, found expression!", .{}),
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
	const expTrue = struct {
		fn f(expr: []const u8, ctx: *const Context) !void {
			return try std.testing.expectEqual(true, parse(expr, 1, ctx));
		}
	}.f;
	const expFalse = struct {
		fn f(expr: []const u8, ctx: *const Context) !void {
			return try std.testing.expectEqual(false, parse(expr, 1, ctx));
		}
	}.f;
	const expError = struct {
		fn f(e: ParseError, expr: []const u8, ctx: *const Context) !void {
			return try std.testing.expectError(e, parse(expr, 1, ctx));
		}
	}.f;

	log.setup(std.testing.io);
	defer log.stderr.flush() catch {};

	var ctx = Context.init(gpa);
	defer ctx.deinit(std.testing.io);
	try ctx.macros.put("true", 1);
	try ctx.macros.put("ft", 42);

	// TODO
	try expTrue("true", &ctx);
	try expTrue("(  true )", &ctx);
	try expTrue("(((true)))", &ctx);
	try expTrue("( ( true ) )", &ctx);
	try expTrue("true & true", &ctx);
	try expTrue("true&true", &ctx);
	try expTrue("true = true", &ctx);
	try expTrue("true=true", &ctx);
	try expTrue("(true = true)", &ctx);
	try expTrue("(true = true) = (!false = !false)", &ctx);
	try expTrue("(true = !false) = (!false = true)", &ctx);
	try expTrue("!false", &ctx);
	try expTrue("true | true", &ctx);
	try expTrue("true | false", &ctx);
	try expTrue("false | true", &ctx);
	try expTrue("false & true | true", &ctx);
	try expTrue("true > false", &ctx);
	try expTrue("true>false", &ctx);
	try expTrue("true      >   false", &ctx);
	try expTrue("true >= false", &ctx);
	try expTrue("true>=false", &ctx);
	try expTrue("true      >=   false", &ctx);
	try expTrue("false <= true", &ctx);
	try expTrue("false<=true", &ctx);
	try expTrue("false      <=   true", &ctx);
	try expTrue("ft", &ctx);
	try expTrue("ft = 42", &ctx);
	try expTrue("ft != 0", &ctx);
	try expTrue("ft > 0", &ctx);
	try expTrue("ft >= 0", &ctx);
	try expTrue("ft < 43", &ctx);
	try expTrue("ft <= 43", &ctx);
	try expTrue("ft > true", &ctx);

	try expFalse("false", &ctx);
	try expFalse("(false)", &ctx);
	try expFalse("false | false", &ctx);
	try expFalse("false & false", &ctx);
	try expFalse("false < false", &ctx);
	try expFalse("false > false", &ctx);
	try expFalse("false | false & false", &ctx);
	try expFalse("false & (true | true)", &ctx);

	const DoubleEquals = ParseError.DoubleEquals;
	try expError(DoubleEquals, "a == b", &ctx);
	try expError(DoubleEquals, "a==b", &ctx);
	try expError(DoubleEquals, "a ==b", &ctx);
	try expError(DoubleEquals, "a== b", &ctx);
	try expError(DoubleEquals, "a   ==       b", &ctx);
	// TODO NOW DEBUG
	try expError(DoubleEquals, "(a | b) == (c & d | (e + f))", &ctx);

	try expError(ParseError.UnexpectedOperator, "true < = false", &ctx);
}

fn parseGates(expr: []const u8, ctx: *const Context) ParseError!bool {
	// These variable could ofc also be false and '|', respectively.
	var result = true;
	var matched: u8 = '&';

	var it = ParseIterator.init(expr, "&|");
	while (try it.next()) |next| {
		std.debug.print("parseGates/next '{s}'\n", .{next.item});
		const parse_result: bool = if (next.item[0] == '(') parse_result: {
			const parens_unwrapped: []const u8 = unwrapParens(next.item);
			std.debug.print("unwrapped\n", .{});
			break :parse_result try parseGates(parens_unwrapped, ctx);
		} else try parseCmp(next.item, ctx);

		result = switch (matched) {
			'&' => result and parse_result,
			'|' => result or parse_result,
			else => unreachable
		};
		matched = next.matched;
	}
	return result;
}

// TODO FINAL document the cmp behavior (like a<b<c)
fn parseCmp(expr: []const u8, ctx: *const Context) ParseError!bool {
	std.debug.print("parseCmp '{s}'\n", .{expr});
	const nextAdjusted = struct {
		/// Instead of returning an item and the matched token, this function looks forward
		/// and alters the upcoming string to determine the correct comparison operator.
		fn f(it: *ParseIterator)
		NextAdjustedError!struct {[]const u8, ?CompareOperator} {
			const next: ParseIterator.Next = (try it.next()).?;
			var buf: []const u8 = next.item;
			if (buf.len == 0) return NextAdjustedError.UnexpectedOperator;
			if (next.matched == 0) return .{buf, null};

			if (buf[buf.len - 1] == '!') switch (next.matched) {
				'<', '>' => return NextAdjustedError.UnexpectedBangOperator,
				'=' => {
					buf = buf[0..buf.len - 1];
					return .{buf, .neq};
				},
				else => unreachable
			};
			switch (next.matched) {
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
			std.debug.print("unwrapping\n", .{});
			const parens_unwrapped: []const u8 = unwrapParens(expr);
			// TODO TEST why are we using expr here instead of lhs_buf?
			const lhs: bool = try parseGates(parens_unwrapped, ctx);
			break :lhs @intFromBool(lhs);
		}
		break :lhs try termValue(lhs_buf, ctx);
	};
	var cmp: CompareOperator = maybe_cmp orelse return lhs > 0;

	while (true) {
		const slice: []const u8, const new_cmp: ?CompareOperator = try nextAdjusted(&it);
		const rhs: MacroInt = rhs: {
			if (slice[0] == '(') {
				std.debug.print("unwrapping\n", .{});
				const parens_unwrapped: []const u8 = unwrapParens(slice);
				const rhs_bool: bool = try parseGates(parens_unwrapped, ctx);
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

	if (negate) return @intFromBool(value == 0);
	return value;
}

/// Returns an error if iterator item contains syntax error.
fn validateLiteral(buf: []const u8) ValidateLiteralError!void {
	if (buf.len == 0) return ValidateLiteralError.Empty;
	for (buf) |c| switch (c) {
		' ', '(' => return ValidateLiteralError.UnexpectedExpression,
		')' => return ValidateLiteralError.UnexpectedRparen,
		else => continue
	};
}

// TODO this function should errhandle the condition
/// Called when first character in buffer is opening parenthesis.
/// TODO NOW change this comment
/// Returns index of corresponding closing parenthesis preceeding `self.expr`.
/// Returns `error.UnclosedParenthesis` if there is no closing parenthesis.
/// Does not log.
fn findCloseParen(buf: []const u8) error{UnclosedParenthesis}!usize {
	std.debug.print("findCloseParen '{s}'\n", .{buf});
	var result: usize = 1;
	var scope: usize = 1;
	while (result < buf.len) : (result += 1) switch (buf[result]) {
		'(' => scope += 1,
		')' => {
			scope -= 1;
			if (scope == 0) return result;
		},
		else => continue
	};
	return error.UnclosedParenthesis;
}

/// Assumes that `input` is enclosed in parentheses.
/// Returns slice of it with parens removed and whitespace of remainder trimmed.
fn unwrapParens(buf: []const u8) []const u8 {
	std.debug.print("unwrapParens '{s}'\n", .{buf});
	const end: usize = findCloseParen(buf) catch unreachable;
	return std.mem.trim(u8, buf[1..end], " \t");
}

// TODO NOW DEBUG .if false & (true | true)

// TODO TEST
// a < b < c
// a<b<c

// TODO TEST invalid
// a &
// a |
// a <
// & a
// | a
// < a
// == a
// a == b
// a =
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
// a << b
// a < < b
// a >> b
// a > > b
// a <> b
// a < > b
// a <=> b
// a => b

// TODO TEST unsure
// a<b

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
