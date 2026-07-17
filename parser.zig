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

	fn init(expr: []const u8, tokens: []const u8) ParseIterator {
		return .{ .expr = expr, .tokens = tokens };
	}

	/// If not null, returns next item in the iterator, respecting parentheses and matched
	/// token.
	/// Returns null if `self.condition` was iterated through completely.
	/// Returns `error.UnclosedParenthesis` if expression contains unclosed opening
	/// parenthesis.
	/// Does not log.
	fn next(self: *ParseIterator) error{UnclosedParenthesis}!?Next {
		if (self.expr.len == 0) return null;
		self.expr = a.trimWStart(self.expr);

		var i: usize = 0;
		while (i < self.expr.len) : (i += 1) {
			if (self.expr[i] == '(') {
				i += try findCloseParen(self.expr[i..]);
				continue;
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

	/// Instead of returning an item and the matched token, this function looks
	/// forward and alters the upcoming string to determine the correct comparison
	/// operator.
	fn nextAdjusted(self: *ParseIterator) NextAdjustedError!struct {[]const u8, ?CompareOperator} {
		std.debug.assert(std.mem.eql(u8, self.tokens, "<>="));

		const nx: ParseIterator.Next = (try self.next()).?;
		if (nx.item.len == 0) return NextAdjustedError.UnexpectedOperator;
		// If the entire slice was returned, pass it forth.
		if (nx.matched == 0) return .{nx.item, null};

		if (nx.item[nx.item.len - 1] == '!') switch (nx.matched) {
			'<', '>' => return NextAdjustedError.UnexpectedBangOperator,
			'=' => {
				const buf = nx.item[0..nx.item.len - 1];
				return .{buf, .neq};
			},
			else => unreachable
		};
		switch (nx.matched) {
			'<' => {
				if (self.expr[0] == '=') {
					self.expr = self.expr[1..];
					return .{nx.item, .lte};
				}
				return .{nx.item, .lt};
			},
			'>' => {
				if (self.expr[0] == '=') {
					self.expr = self.expr[1..];
					return .{nx.item, .gte};
				}
				return .{nx.item, .gt};
			},
			'=' => {
				if (self.expr[0] == '=') return NextAdjustedError.DoubleEquals;
				return .{nx.item, .eq};
			},
			else => unreachable
		}
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
	const value: MacroInt = parseGates(expr, ctx) catch |e| {
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
				log.errWithLineNr(linenr, "Unexpected operator after '!' !", .{}),
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
	return value != 0;
}

test parse {
	const expTrue = struct {
		fn expTrue(expr: []const u8, ctx: *const Context) !void {
			return try std.testing.expectEqual(true, parse(expr, 1, ctx));
		}
	}.expTrue;
	const expFalse = struct {
		fn expFalse(expr: []const u8, ctx: *const Context) !void {
			return try std.testing.expectEqual(false, parse(expr, 1, ctx));
		}
	}.expFalse;
	const expError = struct {
		fn expError(e: ParseError, expr: []const u8, ctx: *const Context) !void {
			return try std.testing.expectError(e, parse(expr, 1, ctx));
		}
	}.expError;

	log.setup(std.testing.io);
	defer log.stderr.flush() catch {};

	var ctx = Context.init(gpa);
	defer ctx.deinit(std.testing.io);
	try ctx.macros.put("true", 1);
	try ctx.macros.put("ft", 42);

	try expTrue("1", &ctx);
	try expTrue("42", &ctx);
	try expTrue("!0", &ctx);
	try expTrue("-1", &ctx);
	try expTrue("true", &ctx);
	try expTrue("(  true )", &ctx);
	try expTrue("(((true)))", &ctx);
	try expTrue("( ( true ) )", &ctx);
	try expTrue("( 27 )", &ctx);
	try expTrue("true & true", &ctx);
	try expTrue("true&true", &ctx);
	try expTrue("true = true", &ctx);
	try expTrue("true=true", &ctx);
	try expTrue("!false", &ctx);
	try expTrue("true | true", &ctx);
	try expTrue("true | false", &ctx);
	try expTrue("false | true", &ctx);
	try expTrue("false|true", &ctx);
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
	try expTrue("(27) != (1)", &ctx);
	try expTrue("(27) > (1)", &ctx);
	try expTrue("1 < 2 < 3", &ctx);
	try expTrue("(true = true)", &ctx);
	try expTrue("(true = true) = (false = false)", &ctx);
	try expTrue("(true = true) = (!false = !false)", &ctx);
	try expTrue("(true = !false) = (!false = true)", &ctx);
	try expTrue("(true | false) = 1", &ctx);
	try expTrue("(true > b) | (c & d)", &ctx);

	try expFalse("0", &ctx);
	try expFalse("-0", &ctx);
	try expFalse("!1", &ctx);
	try expFalse("!ft", &ctx);
	try expFalse("false", &ctx);
	try expFalse("(false)", &ctx);
	try expFalse("( 0 )", &ctx);
	try expFalse("( false )", &ctx);
	try expFalse("false | false", &ctx);
	try expFalse("false & false", &ctx);
	try expFalse("false < false", &ctx);
	try expFalse("false > false", &ctx);
	try expFalse("1 < 3 < 2", &ctx);
	try expFalse("false | false & false", &ctx);
	try expFalse("false & (true | true)", &ctx);
	try expFalse("a <! b", &ctx);
	try expFalse("5 > 2 & 1 & 0", &ctx);

	const DoubleEquals = ParseError.DoubleEquals;
	try expError(DoubleEquals, "a == b", &ctx);
	try expError(DoubleEquals, "a==b", &ctx);
	try expError(DoubleEquals, "a ==b", &ctx);
	try expError(DoubleEquals, "a== b", &ctx);
	try expError(DoubleEquals, "a   ==       b", &ctx);
	try expError(DoubleEquals, "(a | b) == (c & d | (e + f))", &ctx);

	const UnclosedParenthesis = ParseError.UnclosedParenthesis;
	try expError(UnclosedParenthesis, "(a", &ctx);
	try expError(UnclosedParenthesis, "(ft != true", &ctx);
	try expError(UnclosedParenthesis, "(1 = true) = false)", &ctx);
	try expError(UnclosedParenthesis, "(((true))", &ctx);

	const UnexpectedBangOperator = ParseError.UnexpectedBangOperator;
	try expError(UnexpectedBangOperator, "a!", &ctx);
	try expError(UnexpectedBangOperator, "a!b", &ctx);
	try expError(UnexpectedBangOperator, "a ! b", &ctx);
	try expError(UnexpectedBangOperator, "a|!b", &ctx);
	try expError(UnexpectedBangOperator, "a|!|b", &ctx);
	try expError(UnexpectedBangOperator, "a !! b", &ctx);

	const UnexpectedOperator = ParseError.UnexpectedOperator;
	try expError(UnexpectedOperator, "true < = false", &ctx);
	try expError(UnexpectedOperator, "& a", &ctx);
	try expError(UnexpectedOperator, "a &", &ctx);
	try expError(UnexpectedOperator, "a &| b", &ctx);
	try expError(UnexpectedOperator, "a & & b", &ctx);
	try expError(UnexpectedOperator, "a <> b", &ctx);
	try expError(UnexpectedOperator, "1 < 2 < 3 <", &ctx);

	const Empty = ParseError.Empty;
	try expError(Empty, "", &ctx);
	try expError(Empty, " ", &ctx);
	try expError(Empty, "       ", &ctx);
	try expError(Empty, "(  )", &ctx);
	try expError(Empty, "( () )", &ctx);
	try expError(Empty, "((((()))))", &ctx);
	try expError(Empty, "() ()", &ctx);
	try expError(Empty, "()()()", &ctx);

	const UnexpectedExpression = ParseError.UnexpectedExpression;
	try expError(UnexpectedExpression, "a b", &ctx);
	try expError(UnexpectedExpression, "true true", &ctx);
	try expError(UnexpectedExpression, "a()", &ctx);
	try expError(UnexpectedExpression, "a - b", &ctx);
	try expError(UnexpectedExpression, "(a | b) = (c & d | (e + f))", &ctx);

	const UnexpectedRparen = ParseError.UnexpectedRparen;
	try expError(UnexpectedRparen, ")", &ctx);
	try expError(UnexpectedRparen, "())", &ctx);
	try expError(UnexpectedRparen, "a | b  )", &ctx);

	const UndefinedMacro = ParseError.UndefinedMacro;
	ctx.safe = true;
	_ = ctx.macros.remove("true");
	_ = ctx.macros.remove("ft");
	try expError(UndefinedMacro, "a", &ctx);
	try expError(UndefinedMacro, "false", &ctx);
	try expError(UndefinedMacro, "var0", &ctx);
	try expError(UndefinedMacro, "var0", &ctx);
	try expError(UndefinedMacro, "true", &ctx);
	try expError(UndefinedMacro, "ft", &ctx);
	ctx.safe = false;
	try ctx.macros.put("true", 1);
	try ctx.macros.put("ft", 42);
	
	const UnrepresentableNumber = ParseError.UnrepresentableNumber;
	const bits: u32 = @typeInfo(MacroInt).int.bits;
	const LargerInt = @Int(.signed, bits +| 1);
	const largest = std.math.maxInt(LargerInt);
	const smallest = std.math.minInt(LargerInt);
	const largest_str = std.fmt.allocPrint(gpa, "{d}", .{largest});
	const smallest_str = std.fmt.allocPrint(gpa, "{d}", .{smallest});
	try expError(UnrepresentableNumber, largest_str, &ctx);
	try expError(UnrepresentableNumber, smallest_str, &ctx);
	gpa.free(largest_str);
	gpa.free(smallest_str);
}

fn parseGates(expr: []const u8, ctx: *const Context) ParseError!MacroInt {
	if (a.trimW(expr).len == 0) return ParseError.Empty;

	var it = ParseIterator.init(expr, "&|");
	var result: MacroInt, var matched: u8 = result: {
		const next: ParseIterator.Next = (try it.next()).?;
		break :result .{try parseCmp(next.item, ctx), next.matched};
	};

	while (try it.next()) |next| {
		std.debug.print("parseGates/next '{s}' ({c})\n", .{next.item, matched});
		const parse_result: MacroInt = try parseCmp(next.item, ctx);
		result = switch (matched) {
			'&' => @intFromBool((result != 0) and (parse_result != 0)),
			'|' => @intFromBool((result != 0) or (parse_result != 0)),
			else => unreachable
		};
		matched = next.matched;
	}
	return result;
}

// TODO FINAL document the cmp behavior (like a<b<c)
fn parseCmp(expr: []const u8, ctx: *const Context) ParseError!MacroInt {
	std.debug.print("parseCmp '{s}'\n", .{expr});

	var it = ParseIterator.init(expr, "<>=");

	const lhs_buf: []const u8, const maybe_cmp: ?CompareOperator = try it.nextAdjusted();
	var lhs: MacroInt = try termValue(lhs_buf, ctx);
	var cmp: CompareOperator = maybe_cmp orelse return lhs;

	while (true) {
		const slice: []const u8, const new_cmp: ?CompareOperator = try it.nextAdjusted();
		const rhs: MacroInt = try termValue(slice, ctx);
		const holds: bool = switch (cmp) {
			.lt => lhs < rhs,
			.lte => lhs <= rhs,
			.eq => lhs == rhs,
			.gt => lhs > rhs,
			.gte => lhs >= rhs,
			.neq => lhs != rhs
		};
		if (!holds) return 0;

		cmp = new_cmp orelse break;
		lhs = rhs;
	}

	return 1;
}

/// TODO COMMENT
fn termValue(term: []const u8, ctx: *const Context) ParseError!MacroInt {
	if (term[0] == '(') {
		const parens_unwrapped: []const u8 = unwrapParens(term);
		return try parseGates(parens_unwrapped, ctx);
	}

	const trim_nots = std.mem.trimStart(u8, term, "!");
	const negate: bool = (term.len - trim_nots.len) & 1 == 1;
	const lit = std.mem.trim(u8, trim_nots, " \t");

	const value: MacroInt = std.fmt.parseInt(MacroInt, lit, 10) catch |e| value: {
		if (e == error.Overflow) return TermValueError.UnrepresentableNumber;
		try validateLiteral(lit);

		break :value ctx.macros.get(lit) orelse {
			if (ctx.safe) return TermValueError.UndefinedMacro;
			break :value 0;
		};
	};

	if (negate) return @intFromBool(value == 0);
	return value;
}

/// Returns an error if supposed literal contains syntax error.
fn validateLiteral(buf: []const u8) ValidateLiteralError!void {
	std.debug.assert(buf.len > 0);
	for (buf) |c| switch (c) {
		' ', '(' => return ValidateLiteralError.UnexpectedExpression,
		')' => return ValidateLiteralError.UnexpectedRparen,
		else => continue
	};
}

/// Returns index of corresponding closing parenthesis to the first opening one.
/// Returns `error.UnclosedParenthesis` if there is no closing parenthesis.
/// Does not log.
fn findCloseParen(buf: []const u8) error{UnclosedParenthesis}!usize {
	std.debug.assert(buf[0] == '(');
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

// TODO TEST
// a < b < c
// a<b<c
// TEST all ParseErrors

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
