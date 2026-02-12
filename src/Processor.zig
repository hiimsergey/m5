const std = @import("std");
const a = @import("alias.zig");
const arguments = @import("arguments.zig");
const parser = @import("parser.zig");

const Allocating = std.Io.Writer.Allocating;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const File = std.fs.File;
const StringHashMap = std.StringHashMap;

const E = error.Generic;

// Token messaging what kind of argument is expected next
const ExpectationStatus = enum(u8) {nothing, output, prefix};
const KV = struct { key: []const u8, value: []const u8 };
const WriteLine = enum(u8) {no, yes, ignore};

const Self = @This();

inputs: ArrayList([]const u8),
macros: StringHashMap([]const u8),
prefix: []const u8,
verbose: bool,

pub fn init(gpa: Allocator) !Self {
	return .{
		.inputs = try ArrayList([]const u8).initCapacity(gpa, 2),
		.macros = StringHashMap([]const u8).init(gpa),
		.prefix = "",
		.verbose = false
	};
}

pub fn deinit(self: *Self, gpa: Allocator) void {
	self.inputs.deinit(gpa);
	self.macros.deinit();
}

/// Interpret arguments, assuming they have a correct format, and process
/// all input files into their respective outputs.
pub fn run(self: *Self, gpa: Allocator, args: [][:0]u8) !void {
	var expecting = ExpectationStatus.nothing;

	// Don't log anything if processing to stdout to avoid mixing with the file
	// content.
	self.verbose = a.contains_str(args, "-v") and a.contains_str(args, "-o");

	for (args[1..]) |arg| {
		switch (expecting) {
			.output => {
				var file = std.fs.cwd().createFile(arg, .{}) catch {
					a.errtag();
					a.errln("Could not create output file '{s}'!", .{arg});
					return E;
				};
				defer file.close();

				var writer_buf: [1024]u8 = undefined;
				var writer = file.writer(&writer_buf);

				try self.process(gpa, &writer);
				self.inputs.clearRetainingCapacity();
				expecting = .nothing;
				continue;
			},
			.prefix => {
				self.prefix = arg;
				expecting = .nothing;
				continue;
			},
			.nothing => {}
		}
		if (a.startswith(arg, "-D")) {
			const definition = arg["-D".len..];
			const pair: KV = blk: {
				const equals_i = std.mem.indexOfScalar(u8, definition, '=') orelse
					break :blk .{ .key = definition, .value = "" };
				break :blk .{
					.key = definition[0..equals_i],
					.value = definition[equals_i + 1..]
				};
			};
			try self.macros.put(pair.key, pair.value);
		}
		else if (a.eql(arg, "-p")) expecting = .prefix
		else if (a.eql(arg, "-o")) expecting = .output
		else if (arg[0] == '-') continue // gotta be the -v flag
		else {
			// Input file
			try self.validate_input(gpa, arg);
			try self.inputs.append(gpa, arg);
		}
	}

	if (self.inputs.items.len > 0) try self.process(gpa, &a.stdout);
}

/// Check whether the input file lacks any m5 syntax errors.
fn validate_input(self: *Self, gpa: Allocator, input: []const u8) !void {
	var file = std.fs.cwd().openFile(input, .{ .mode = .read_only }) catch {
		a.errtag();
		a.errln("Could not open input file '{s}'!", .{input});
		return E;
	};
	defer file.close();

	var reader_buf: [1024]u8 = undefined;
	var reader = file.reader(&reader_buf);

	var allocating = Allocating.init(gpa);
	defer allocating.deinit();

	var linenr: usize = 1;
	var scope: usize = 0;

	while (
		reader.interface.streamDelimiterEnding(&allocating.writer, '\n') catch 0 > 0
	) : ({
		allocating.clearRetainingCapacity();
		reader.interface.toss(
			@intFromBool(reader.interface.seek < reader.interface.end)
		); // skip newline but not when the file doesn't end with one
		linenr += 1;
	}) {
		const line = allocating.written();
		if (!a.startswith(line, self.prefix)) continue;

		const line_wo_prefix = blk: {
			const wo_leading_whitespace = a.trim_ws_left(line);
			const prefix_skipped = wo_leading_whitespace[self.prefix.len..];
			break :blk a.trim_ws_left(prefix_skipped);
		};
		if (a.startswith(line_wo_prefix, "if")) {
			scope += 1;
			const condition = line_wo_prefix["if".len..];
			try parser.validate(condition, input, linenr);
		}
		// TODO NOW this is both lowk inefficient and results in an proper errmsg
		// with lines like "m5 else          X         "
		// TODO REMOVE elif keyword
		else if (a.startswith(line_wo_prefix, "else")) {
			if (std.mem.trimRight(u8, line_wo_prefix, " \t").len == "else".len) continue;

			const space_i = std.mem.indexOf(u8, line_wo_prefix, " \t") orelse {
				a.errtag();
				a.errln(
					\\{s}, line {d}: Invalid keyword '{s}'!
					\\Should be 'if', 'else' or 'end'!
					, .{input, linenr, line_wo_prefix}
				);
				return E;
			};

			if (scope == 0) {
				a.errtag();
				a.errln(
					"{s}, line {d}: There can be no else without an if clause prior!",
					.{input, linenr}
				);
				return E;
			}
			
			const else_clause = a.trim_ws_left(line_wo_prefix[space_i..]);
			if (!a.startswith(else_clause, "if")) {
				a.errtag();
				a.errln(
					"{s}, line {d}: Expected 'else if <condition>', got invalid sequence 'else {s}'!",
					.{input, linenr, else_clause}
				);
				return E;
			}

			const condition = else_clause["if".len..];
			try parser.validate(condition, input, linenr);
		}
		else if (a.startswith(line_wo_prefix, "end")) {
			if (scope == 0) {
				a.errtag();
				a.errln(
					"{s}, line {d}: There can be no end without an if clause prior!",
					.{input, linenr}
				);
				return E;
			}
			scope -= 1;
		}
		else {
			const first_word = blk: {
				const space_i = std.mem.indexOfScalar(u8, line_wo_prefix, ' ')
					orelse line_wo_prefix.len;
				break :blk line_wo_prefix[0..space_i];
			};
			a.errtag();
			a.errln(
				\\{s}, line {d}: Invalid keyword '{s}'!
				\\Should be 'if', 'else' or 'end'!
				, .{input, linenr, first_word}
			);
			return E;
		}
	}

	if (scope == 0) return;
	a.errtag();
	a.errln("{s}, line {d}: If clause lacks end keyword!", .{input, linenr});
	return E;
}

fn process(self: *Self, gpa: Allocator, writer: *File.Writer) !void {
	for (self.inputs.items) |input| {
		var file = try std.fs.cwd().openFile(input, .{ .mode = .read_only });
		defer file.close();

		var reader_buf: [1024]u8 = undefined;
		var reader = file.reader(&reader_buf);

		var allocating = Allocating.init(gpa);
		defer allocating.deinit();

		try self.read_lines(&allocating, &reader, writer);
		// TODO FINAL TEST
		if (self.verbose) a.println("Processed {s}!", .{input});
	}
	try writer.interface.flush();
}

fn read_lines(
	self: *Self, allocating: *Allocating,
	reader: *File.Reader, writer: *File.Writer
) !void {
	// TODO NOTE PLAN
	// when declaring a scope .ignore, count next scopes but wait until the
	// outermost scope ends
	// then set wl to .yes
	//
	// on elif
	// if wl was ignore, keep it ignore
	// otherwise recompute

	var linenr: usize = 1;
	var scope: usize = 0;
	var ignore_scopes: usize = 0;
	var write_line: WriteLine = .yes;

	while (
		reader.interface.streamDelimiterEnding(&allocating.writer, '\n') catch 0 > 0
	) : ({
		allocating.clearRetainingCapacity();
		reader.interface.toss(
			@intFromBool(reader.interface.seek < reader.interface.end)
		); // skip newline but not when the file doesn't end with one
		linenr += 1;
	}) {
		const line: []u8 = allocating.written();
		const trimmed: []const u8 = a.trim_ws_left(line);

		if (!a.startswith(trimmed, self.prefix)) {
			if (write_line == .yes) try writer.interface.print("{s}\n", .{line});
			continue;
		}

		const condition_line = a.trim_ws_left(trimmed[self.prefix.len..]);
		if (a.startswith(condition_line, "if")) {
			scope += 1;
			if (write_line != .yes) {
				ignore_scopes += 1;
				continue;
			}
			write_line = switch (parser.parse(condition_line["if".len..], &self.macros)) {
				true => .yes,
				false => .no
			};
		}
		else if (a.startswith(condition_line, "else")) {
			if (std.mem.trimRight(u8, condition_line, " \t").len == "else".len) {
				write_line = if (write_line != .no) .ignore else .yes;
				continue;
			}
			write_line = switch (write_line) {
				.yes, .ignore => .ignore,
				else => blk: {
					const else_skipped = a.trim_ws_left(condition_line["else".len..]);
					const condition = a.trim_ws_left(else_skipped["if".len..]);
					const parse_true = parser.parse(condition, &self.macros);
					break :blk if (parse_true) .yes else .no;
				}
			};
		}
		else if (a.startswith(condition_line, "end")) {
			if (ignore_scopes == 0) write_line = .yes
			else ignore_scopes -= 1;
		}
	}
}
