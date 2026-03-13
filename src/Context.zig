const std = @import("std");
const log = @import("log.zig");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
/// Process-specific metadata
const Self = @This();

const validateKey = @import("root").validateKey;

flags: packed struct(u8) {
	// TODO FINAL CHECK implemented
	verbose: bool = false,
	// TODO FINAL CHECK implemented
	safe: bool = false,
	_: u6 = 0
} = .{},
output: ?File = null,
input: ?File = null,
prefix: ?[]const u8 = null,
_prefix_buf: [64]u8 = undefined,
macros: MacroMap,
labels: LabelMap,

pub const MacroInt = isize;
pub const MacroMap = std.StringHashMap(MacroInt);
const LabelMap = std.StringHashMap(Position);

const Position = struct { seek: usize, linenr: usize };

const Keyword = enum(u8) {
	@"if", @"else", end,
	label, goto, after, @"resume",
	define,
	write,
	back
};

const AfterState = enum(u8) {
	/// There is no after label
	none,
	/// There is after label, but currently not running it
	has,
	/// Currently running after label
	in
};

const WriteState = enum(u8) {
	/// Just pass next line to output
	write,
	/// Don't write next line until end of scope or truthy else clause
	dont_write,
	/// Don't write next line until end of scope
	ignore,
	/// Don't write next line until finding label definition or EOF
	find_label_goto,
	/// Don't write next line until finding label definition or EOF,
	/// then jump back to where this state was set
	find_label_after
};

const keyword_map = std.StaticStringMap(Keyword).initComptime(kvs: {
	const fields = @typeInfo(Keyword).@"enum".fields;
	var result: [fields.len]struct{ []const u8, Keyword } = undefined;
	for (fields, 0..) |field, i|
		result[i] = .{ field.name, @as(Keyword, @enumFromInt(field.value)) };
	break :kvs result;
});

pub fn init(gpa: Allocator) Self {
	return .{
		.macros = MacroMap.init(gpa),
		.labels = LabelMap.init(gpa)
	};
}

pub fn deinit(self: *Self) void {
	if (self.output) |file| file.close();
	if (self.input) |file| file.close();
	self.macros.deinit();
}

pub fn run(self: *Self, gpa: Allocator) error{Generic, System}!void {
	// TODO CHECK if you've handled all errors
	// handled by m5's validate* functions

	var allocating = std.Io.Writer.Allocating.init(gpa);
	defer allocating.deinit();

	var reader_buf: [1024]u8 = undefined;
	var reader_wrapper = self.input.?.reader(&reader_buf);
	const reader = &reader_wrapper.interface;

	var writer_buf: [1024]u8 = undefined;
	var writer_wrapper = self.output.?.writer(&writer_buf);
	const writer = &writer_wrapper.interface;

	// TODO ERRHANDLE too long label in definition
	// TODO ERRHANDLE too long prefix in definition
	var _finding_label_buf: [64]u8 = undefined;
	var finding_label: []const u8 = "";
	var after_state = AfterState.none;
	var after_pos: Position = undefined;

	var state = WriteState.write;
	var linenr: usize = 1;
	var scope: usize = 0;
	var ignored_scopes: usize = 0;

	// TODO CONSIDER MOVE STRUCT
	var last_jumped: Position = undefined;
	var last_jumped_scope: usize = 0;
	var last_ignored_scopes: usize = 0;

	// TODO TEST off by one error when jumping

	// TODO TEST requirements for a line-by-line while loop
	// - handles missing \n on last line
	// - doesnt stop on blank lines
	while (reader.streamDelimiterEnding(&allocating.writer, '\n') catch 0 > 0) : ({
		if (after_state == .has) {
			after_state = .in;

			last_jumped = Position{ .seek = reader.seek, .linenr = linenr };
			last_jumped_scope = scope;
			last_ignored_scopes = ignored_scopes;

			reader.seek = after_pos.seek;
			linenr = after_pos.linenr;
			scope = 0;
			ignored_scopes = 0;
		}
		allocating.clearRetainingCapacity();
		// Skips newline but not if file doesn't end with one.
		reader.toss(@intFromBool(reader.seek < reader.end));
		linenr += 1;
		// TODO ADD after implementation
	}) {
		const cmd = cmd: {
			const line = allocating.written();
			const line_trimmed = trimWsStart(line);
			if (!startsWith(line_trimmed, self.prefix.?)) {
				if (state == .write)
					writer.print("{s}\n", .{line}) catch return error.System;
				continue;
			}
			break :cmd line_trimmed[self.prefix.?.len..];
		};
		var iter = std.mem.tokenizeAny(u8, cmd, " \t");

		const keyword: []const u8 = iter.next() orelse {
			log.errWithLineNr(
				linenr, "Expected keyword, found end of line!", .{});
			return error.Generic;
		};
		const keyword_arm: Keyword = keyword_map.get(keyword) orelse {
			log.errWithLineNr(linenr, "Invalid keyword '{s}'!", .{keyword});
			return error.Generic;
		};

		switch (keyword_arm) {
			.@"if" => {
				scope += 1;
				switch (state) {
					.write => {
						const expression = trimWsEnd(cmd[iter.index..]);
						if (expression.len == 0) {
							log.errWithLineNr(linenr,
								"'if' clause expects expression!", .{});
							return error.Generic;
						}

						if (try parser.parse(expression, linenr, &self.macros)) continue;
						state = .dont_write;
					},
					.dont_write, .ignore => ignored_scopes += 1,
					// TODO CONSIDER automatically setting scope to 0 when entering find label
					.find_label_goto, .find_label_after => {}
				}
			},
			.@"else" => {
				switch (state) {
					.write => state = .ignore,
					.dont_write => {
						if (iter.next() == null) {
							state = .write;
							continue;
						}

						const expression = trimWsEnd(cmd[iter.index..]);
						if (expression.len == 0) {
							log.errWithLineNr(linenr,
								"'else' clause expects expression!", .{});
							return error.Generic;
						}

						if (try parser.parse(expression, linenr, &self.macros))
							state = .write
						else state = .dont_write;
					},
					.ignore, .find_label_goto, .find_label_after => {}
				}
			},
			.end => {
				if (iter.next() != null) {
					log.errWithLineNr(
						linenr,
						"There can be nothing following 'end'!", .{});
					return error.Generic;
				}

				switch (state) {
					.write, .dont_write => {
						state = .write;
						if (scope == 0) {
							log.errWithLineNr(
								linenr,
								"There can be no 'end' without prior 'if' clause!", .{});
							return error.Generic;
						}
					},
					.ignore => {
						if (ignored_scopes == 0) state = .write
						else ignored_scopes -= 1;
					},
					.find_label_goto, .find_label_after => {}
				}
				scope -= 1;
			},
			.label => {
				// TODO CONSIDER
				if (scope > 0) {
					log.errWithLineNr(linenr,
						"You can't declare labels inside of 'if' clauses!", .{});
					return error.Generic;
				}

				const label = trimWsEnd(cmd[iter.index..]);
				if (label.len == 0) {
					log.errWithLineNr(linenr,
						"label declaration expects label name!", .{});
					return error.Generic;
				}
				if (label.len > _finding_label_buf.len) {
					log.errWithLineNr(linenr,
						"Label must be at most {d} characters (bytes) lnog!",
						.{_finding_label_buf.len});
					return error.Generic;
				}

				if (redefinition: {
					const maybe_kv = self.labels.fetchPut(label, Position{
						.seek = reader.seek,
						.linenr = linenr
					}) catch return error.System;
					break :redefinition maybe_kv == null or
						maybe_kv.?.value.seek == reader.seek;
				}) {
					log.errWithLineNr(linenr,
						"You can't declare the same label twice!", .{});
					return error.Generic;
				}

				if (std.mem.eql(u8, finding_label, label)) switch (state) {
					.find_label_goto => {
						state = .write;
						scope = 0;
						ignored_scopes = 0;
						finding_label = "";
					},
					.find_label_after => {
						state = .write;
						after_pos = Position{ .seek = reader.seek, .linenr = linenr };
						reader.seek = last_jumped.seek;
						linenr = last_jumped.linenr;
						scope = last_jumped_scope;
						ignored_scopes = last_ignored_scopes;
						finding_label = "";
					},
					else => {}
				};
			},
			.goto => {
				if (state != .write) continue;

				const label = trimWsEnd(cmd[iter.index..]);
				if (label.len == 0) {
					log.errWithLineNr(linenr, "'goto' statement expects label name!", .{});
					return error.Generic;
				}
				if (label.len > _finding_label_buf.len) {
					log.errWithLineNr(linenr,
						"Label must be at most {d} characters (bytes) lnog!",
						.{_finding_label_buf.len});
					return error.Generic;
				}

				const pos = self.labels.get(label) orelse {
					state = .find_label_goto;
					@memcpy(_finding_label_buf[0..label.len], label);
					finding_label = _finding_label_buf[0..label.len];
					continue;
				};

				// TODO CONSIDER MOVE FUNC
				scope = 0;
				ignored_scopes = 0;
				reader.seek = pos.seek;
				linenr = pos.linenr;
			},
			.after => {
				if (state != .write) continue;

				const label = trimWsEnd(cmd[iter.index..]);
				if (label.len == 0) {
					after_state = .none;
					continue;
				}
				if (label.len > _finding_label_buf.len) {
					log.errWithLineNr(linenr,
						"Label must be at most {d} characters (bytes) lnog!",
						.{_finding_label_buf.len});
					return error.Generic;
				}

				after_pos = self.labels.get(label) orelse {
					state = .find_label_after;
					@memcpy(_finding_label_buf[0..label.len], label);
					finding_label = _finding_label_buf[0..label.len];

					// TODO CONSIDER MOVE struct
					last_jumped = Position{ .seek = reader.seek, .linenr = linenr };
					last_jumped_scope = scope;
					last_ignored_scopes = ignored_scopes;
					continue;
				};
			},
			.@"resume" => {
				if (state != .write) continue;
				reader.seek = last_jumped.seek;
				linenr = last_jumped.linenr;
				scope = last_jumped_scope;
				ignored_scopes = last_ignored_scopes;
				after_state = .has;
			},
			.define => {
				// TODO support expressions

				if (state != .write) continue;

				const key = key: {
					const result = iter.next() orelse {
						log.errWithLineNr(linenr,
							"'define' statement needs variable name and value!", .{});
						return error.Generic;
					};
					try validateKey(result);
					break :key result;
				};
				const value = value: {
					// TODO when implementing expression, you probably dont need trimming
					const value_buf = trimWsEnd(cmd[iter.index..]);
					break :value std.fmt.parseInt(MacroInt, value_buf, 10) catch |e| {
						switch (e) {
							error.Overflow => log.errWithLineNr(
								linenr,
								\\Number {s} is not representable!"
								\\Only numbers from {d} to {d} are supported!
								, .{value_buf, std.math.minInt(MacroInt),
									std.math.maxInt(MacroInt)}
							),
							error.InvalidCharacter => log.errWithLineNr(linenr,
								"Value '{s}' is not a valid number!", .{value_buf})
						}
						return error.Generic;
					};
				};

				self.macros.put(key, value) catch return error.System;
			},
			.write => {
				// TODO support math expressions

				if (state != .write) continue;

				const key = key: {
					const cand = iter.next();
					const subkeyword = iter.next();

					if (cand == null or subkeyword != null) {
						log.errWithLineNr(linenr,
							"'write' statement expects a single variable name!", .{});
						return error.Generic;
					}

					break :key cand.?;
				};
				const value: MacroInt = self.macros.get(key) orelse 0;

				writer.print("{d}", .{value}) catch return error.System;
			},
			.back => {
				// TODO CONSIDER support math expressions

				if (state != .write) continue;

				const n: u64 = n: {
					const buf = iter.next() orelse break :n 1;

					if (iter.next() != null) {
						log.errWithLineNr(linenr,
							"'back' statement only takes one argument!", .{});
						return error.Generic;
					}

					break :n std.fmt.parseInt(u64, buf, 10) catch |e| switch (e) {
						error.Overflow => {
							log.errWithLineNr(
								linenr,
								\\Number {s} is not representable!"
								\\Only numbers from {d} to {d} are supported!
								, .{buf, std.math.minInt(u64), std.math.maxInt(u64)}
							);
							return error.Generic;
						},
						error.InvalidCharacter => {
							log.errWithLineNr(linenr,
								"Value '{s}' is not a valid number!", .{buf});
							return error.Generic;
						}
					};
				};

				writer.flush() catch return error.System;
				writer_wrapper.seekTo(writer_wrapper.pos - n) catch return error.System;
			}
		}
	}

	switch (state) {
		.write => {},
		.dont_write, .ignore => {
			log.err(
				"'if' clause expects scope termination with corresponding 'end' keyword!",
				.{});
			return error.Generic;
		},
		.find_label_goto, .find_label_after => {
			log.err("No such label '{s}'!", .{finding_label});
			return error.Generic;
		},
	}

	// TODO FINAL ADD new kind of verbose code
	// TODO PLAN
	// for every line
	//     if not startswith prefix: ignore
	//     for state:
	//         write              -> writing
	//         dont_write, ignore -> not writing
	//         find_label         -> state = write
	//     TODO NOTE only trigger goto if state==write
	//     if safe and variable unknown, throw error
	//     if writing mode: write line
	// if not found label, throw error
	// if verbose, print "Processed <input>..."

	writer.flush() catch return error.System;
	self.output.?.setEndPos(writer_wrapper.pos) catch return error.System;
}

/// Wrapper around std.mem.startsWith.
fn startsWith(haystack: []const u8, needle: []const u8) bool {
	return std.mem.startsWith(u8, haystack, needle);
}

/// Wrapper around std.mem.trimStart
fn trimWsStart(buf: []const u8) []const u8 {
	return std.mem.trimStart(u8, buf, " \t");
}

/// Wrapper around std.mem.trimEnd
fn trimWsEnd(buf: []const u8) []const u8 {
	return std.mem.trimEnd(u8, buf, " \t");
}

// TODO ERRHANDLE double label declaration
// TODO ERRHANDLE no label but yes goto
// TODO ERRHANDLE delete file if runtime error
// TODO ERRHANDLE scope becomes -1
// TODO dont call after in after body
// TODO correct back implementation (can you go back in stdout)
// TODO ERRHANDLE back offset larger than write offset
// TODO ERRHANDLE resuming without having jumped to after
// TODO ERRHANDLE resuming with positive scope
