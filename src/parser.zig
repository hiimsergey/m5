const M5Error = @import("error.zig").M5Error;

const State = enum(u8) {
	InExpression,
	InNumber,
	ExpectingExpression,
	ExpectingOperator
};

pub fn validate(condition: []const u8) !void {
	var indentation_level: usize = 0;
	var state = State.InExpression;

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
				if (condition[i + 1] == '=') i += 1;
			},
			'!' => {
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

	if (indentation_level > 0 or (state != .InExpression and state != .InNumber))
		return M5Error.InvalidConditionSyntax;
}

pub fn parse(condition: []const u8) bool {
	_ = condition;
	// TOOD NOW
}
