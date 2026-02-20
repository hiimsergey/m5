const std = @import("std");
const arguments = @import("arguments.zig");
const log = @import("log.zig");
const parser = @import("parser.zig");

const Allocating = std.Io.Writer.Allocating;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const File = std.fs.File;
const StringHashMap = std.StringHashMap;

const stdout = log.stdout;

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
	self.verbose = containsString(args, "-v") and containsString(args, "-o");

	for (args[1..]) |arg| {
		switch (expecting) {
			.output => {
				var file = std.fs.cwd().createFile(arg, .{}) catch {
					log.err("Could not create output file '{s}'!\n", .{arg});
					return E;
				};
				defer file.close();

				var writer_buf: [1024]u8 = undefined;
				var writer = file.writer(&writer_buf);

				try self.process(gpa, &writer.interface);
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
		if (startsWith(arg, "-D")) {
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
		else if (eql(arg, "-p")) expecting = .prefix
		else if (eql(arg, "-o")) expecting = .output
		else if (arg[0] == '-') continue // gotta be the -v flag
		else {
			// Input file
			try self.validateInput(gpa, arg);
			try self.inputs.append(gpa, arg);
		}
	}

	if (self.inputs.items.len > 0) try self.process(gpa, log.stdout);
}

/// Check whether the input file lacks any m5 syntax errors.
fn validateInput(self: *Self, gpa: Allocator, input: []const u8) !void {
	var file = std.fs.cwd().openFile(input, .{ .mode = .read_only }) catch {
		log.err("Could not open input file '{s}'!\n", .{input});
		return E;
	};
	defer file.close();

	var reader_buf: [1024]u8 = undefined;
	var file_reader = file.reader(&reader_buf);
	const reader = &file_reader.interface;

	var allocating = Allocating.init(gpa);
	defer allocating.deinit();

	var linenr: usize = 1;
	var scope: usize = 0;

	while (reader.streamDelimiterEnding(&allocating.writer, '\n') catch 0 > 0) : ({
		allocating.clearRetainingCapacity();
		// Skip newline but not when the file doesn't end with one
		reader.toss(@intFromBool(reader.seek < reader.end));
		linenr += 1;
	}) {
		const line = allocating.written();
		if (!startsWith(line, self.prefix)) continue;

		const line_wo_prefix = blk: {
			const wo_leading_whitespace = trimWsStart(line);
			const prefix_skipped = wo_leading_whitespace[self.prefix.len..];
			break :blk trimWsStart(prefix_skipped);
		};
		if (startsWith(line_wo_prefix, "if")) {
			scope += 1;
			const condition = line_wo_prefix["if".len..];
			try parser.validate(condition, input, linenr);
		}
		// TODO NOW this is both lowk inefficient and results in an proper errmsg
		// with lines like "m5 else          X         "
		else if (startsWith(line_wo_prefix, "else")) {
			if (std.mem.trimRight(u8, line_wo_prefix, " \t").len == "else".len) {
				// else is solitary.
				continue;
			}

			const space_i = std.mem.indexOf(u8, line_wo_prefix, " \t") orelse {
				// Line is a single word starting with "else".
				log.err(
					\\{s}, line {d}: Invalid keyword '{s}'!
					\\Should be 'if', 'else' or 'end'!
					\\
					, .{input, linenr, line_wo_prefix}
				);
				return E;
			};

			// Line's first word is definitely "else".
			if (scope == 0) {
				log.err(
					"{s}, line {d}: There can be no else without an if clause prior!\n",
					.{input, linenr}
				);
				return E;
			}
			
			const else_clause = trimWsStart(line_wo_prefix[space_i..]);
			if (!startsWith(else_clause, "if")) {
				// Line's next word is not "if".
				log.err(
					"{s}, line {d}: Expected 'else if <condition>', " ++
					"got invalid sequence 'else {s}'!\n",
					.{input, linenr, else_clause}
				);
				return E;
			}

			const condition = else_clause["if".len..];
			try parser.validate(condition, input, linenr);
		}
		else if (startsWith(line_wo_prefix, "end")) {
			if (scope == 0) {
				log.err(
					"{s}, line {d}: There can be no end without an if clause prior!\n",
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
			log.err(
				\\{s}, line {d}: Invalid keyword '{s}'!
				\\Should be 'if', 'else' or 'end'!
				\\
				, .{input, linenr, first_word}
			);
			return E;
		}
	}

	if (scope == 0) return;
	log.err("{s}, line {d}: If clause lacks end keyword!\n", .{input, linenr});
	return E;
}

fn process(self: *Self, gpa: Allocator, writer: *std.Io.Writer) !void {
	for (self.inputs.items) |input| {
		var file = try std.fs.cwd().openFile(input, .{ .mode = .read_only });
		defer file.close();

		var reader_buf: [1024]u8 = undefined;
		var reader = file.reader(&reader_buf);

		var allocating = Allocating.init(gpa);
		defer allocating.deinit();

		try self.processLines(&allocating, &reader.interface, writer);
		// TODO FINAL TEST
		if (self.verbose) stdout.print("Processed {s}!\n", .{input}) catch {};
	}
	try writer.flush();
}

fn processLines(
	self: *Self, allocating: *Allocating,
	reader: *std.Io.Reader, writer: *std.Io.Writer
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
		reader.streamDelimiterEnding(&allocating.writer, '\n') catch 0 > 0
	) : ({
		allocating.clearRetainingCapacity();
		reader.toss(
			@intFromBool(reader.seek < reader.end)
		); // skip newline but not when the file doesn't end with one
		linenr += 1;
	}) {
		const line: []u8 = allocating.written();
		const trimmed: []const u8 = trimWsStart(line);

		if (!startsWith(trimmed, self.prefix)) {
			if (write_line == .yes) try writer.print("{s}\n", .{line});
			continue;
		}

		const condition_line = trimWsStart(trimmed[self.prefix.len..]);
		if (startsWith(condition_line, "if")) {
			scope += 1;
			if (write_line != .yes) {
				ignore_scopes += 1;
				continue;
			}
			write_line = if (parser.parse(condition_line["if".len..], &self.macros))
				.yes else .no;
		}
		else if (startsWith(condition_line, "else")) {
			if (std.mem.trimRight(u8, condition_line, " \t").len == "else".len) {
				// else is solitary.
				write_line = if (write_line != .no) .ignore else .yes;
				continue;
			}
			write_line = switch (write_line) {
				.yes, .ignore => .ignore,
				else => blk: {
					const else_skipped = trimWsStart(condition_line["else".len..]);
					const condition = trimWsStart(else_skipped["if".len..]);
					const parse_true = parser.parse(condition, &self.macros);
					break :blk if (parse_true) .yes else .no;
				}
			};
		}
		else if (startsWith(condition_line, "end")) {
			if (ignore_scopes == 0) write_line = .yes
			else ignore_scopes -= 1;
		}
	}
}

const containsString = arguments.containsString;
const eql = arguments.eql;
const startsWith = arguments.startsWith;

fn trimWsStart(buf: []const u8) []const u8 {
	return std.mem.trimStart(u8, buf, " \t");
}
