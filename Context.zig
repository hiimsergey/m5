const std = @import("std");
const a = @import("alias.zig");
const log = @import("log.zig");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;
const File = Io.File;
const Io = std.Io;
/// Process-specific metadata
const Self = @This();

const max_prefix_len = 64;

safe: bool = false,
output: File = undefined,
input: File = undefined,
prefix_buf: [max_prefix_len]u8 = undefined,
prefix_len: std.math.IntFittingRange(0, max_prefix_len - 1) = 0,
macros: MacroMap,

pub const MacroInt = isize;
pub const MacroMap = std.StringHashMap(MacroInt);

const Keyword = enum(u8) {@"if", @"else", end};

const WriteState = enum(u8) {
	/// Just pass next line to output
	write,
	/// Don't write next line until end of scope or truthy else clause.
	/// Set after entering falsy case.
	dont_write,
	/// Don't write next line until end of scope
	/// Set after entering else-clause of truthy case.
	ignore
};

const keyword_map = std.StaticStringMap(Keyword).initComptime(kvs: {
	const fields = @typeInfo(Keyword).@"enum".fields;
	var result: [fields.len]struct { []const u8, Keyword } = undefined;
	for (fields, 0..) |field, i|
		result[i] = .{ field.name, @as(Keyword, @enumFromInt(field.value)) };
	break :kvs result;
});

pub fn init(gpa: Allocator) Self {
	return .{ .macros = MacroMap.init(gpa) };
}

pub fn deinit(self: *Self, io: Io) void {
	self.output.close(io);
	self.input.close(io);
	self.macros.deinit();
}

pub fn run(self: *Self, gpa: Allocator, io: Io) error{User, System}!void {
	var reader_buf: [1024]u8 = undefined;
	var reader_wrapper = self.input.reader(io, &reader_buf);
	const reader = &reader_wrapper.interface;

	var writer_buf: [1024]u8 = undefined;
	var writer_wrapper = self.output.writer(io, &writer_buf);
	const writer = &writer_wrapper.interface;

	var allocating = Io.Writer.Allocating.init(gpa);
	defer allocating.deinit();

	var state = WriteState.write;
	var linenr: usize = 1;
	var scope: usize = 0;
	var ignored_scopes: usize = 0;

	while (true) : ({
		allocating.clearRetainingCapacity();
		// Skips newline but not if file doesn't end with one.
		reader.toss(@intFromBool(reader.seek < reader.end));
		linenr += 1;
	}) {
		const cmd = cmd: {
			const written = reader.streamDelimiterLimit(&allocating.writer, '\n',
				.unlimited) catch return error.System;
			if (written == 0 and reader.seek == reader.end) break;

			const line = allocating.written();
			const line_trimmed = a.trimWStart(line);
			if (!a.startsWith(line_trimmed, self.prefix_buf[0..self.prefix_len])) {
				if (state == .write)
					writer.print("{s}\n", .{line}) catch return error.System;
				continue;
			}
			break :cmd line_trimmed[self.prefix_len..];
		};
		var it = std.mem.tokenizeAny(u8, cmd, " \t");

		const keyword: []const u8 = it.next() orelse {
			log.errWithLineNr(
				linenr, "Expected keyword, found end of line!", .{});
			return error.User;
		};
		// TODO TEST "prefix               if foo"
		const keyword_tag: Keyword = keyword_map.get(keyword) orelse {
			log.errWithLineNr(linenr, "Invalid keyword '{s}'!", .{keyword});
			return error.User;
		};

		switch (keyword_tag) {
			.@"if" => {
				scope += 1;
				switch (state) {
					.write => {
						// TODO TEST "m5 if foo            "
						const expr = a.trimWStart(cmd)["if".len..];
						const parse_result: bool =
							parser.parse(expr, linenr, self) catch
							return error.User;
						if (!parse_result) state = .dont_write;
					},
					.dont_write, .ignore => ignored_scopes += 1
				}
			},
			.@"else" => switch (state) {
				.write => state = .ignore,
				.dont_write => {
					const subkeyword = it.next() orelse {
						state = .write;
						continue;
					};
					if (!std.mem.eql(u8, subkeyword, "if")) {
						log.errWithLineNr(linenr,
							"'else' expects nothing or 'if', found '{s}'!",
							.{subkeyword});
						return error.User;
					}

					const expr = a.trimWEnd(cmd[it.index..]);
					if (expr.len == 0) {
						log.errWithLineNr(linenr,
							"'else if' clause expects expression!", .{});
						return error.User;
					}

					const parse_result: bool =
						parser.parse(expr, linenr, self) catch
						return error.User;
					state = if (parse_result) .write else .dont_write;
				},
				.ignore => {}
			},
			.end => {
				// TODO NOW TEST nested ifs
				if (scope == 0) {
					log.errWithLineNr(
						linenr,
						"There can be no 'end' without preceeding 'if' clause!", .{});
					return error.User;
				}
				scope -= 1;
				if (ignored_scopes == 0) state = .write
				else ignored_scopes -= 1;
			}
		}
	}

	switch (state) {
		.write => {},
		.dont_write, .ignore => {
			log.err(
				"'if' clause expects scope termination with corresponding 'end' keyword!",
				.{});
			return error.User;
		}
	}

	writer.flush() catch return error.System;
}

// TODO ERRHANDLE scope becomes -1
