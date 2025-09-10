const M5Error = @import("error.zig").M5Error;

const State = enum(u8) {
	Ok,
	InExpression,
	ExpectingExpr,
	ExpectingOperator
};

pub fn validate(condition: []const u8) !void {
	var indentation_level: usize = 0;
	var state = State.ExpectingExpr;

	for (condition, 0..) |ch, i| {
		switch (ch) {
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
			'0'...'9', 'a'...'z', 'A'...'Z', '_', '-' => {

			},
			// TODO operators
			else => return M5Error.InvalidConditionSyntax
		}
	}

	if (indentation_level > 0 or state != .Ok) return M5Error.InvalidConditionSyntax;
}

pub fn parse(condition: []const u8) bool {
	_ = condition;
	// TOOD NOW
}
