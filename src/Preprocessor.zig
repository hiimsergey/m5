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

pub fn init(allocator: Allocator) !Self {
	return .{
		.inputs = try ArrayList([]const u8).initCapacity(allocator, 2),
		.macros = StringHashMap([]const u8).init(allocator),
		.prefix = "",
		.verbose = false
	};
}

pub fn deinit(self: *Self, allocator: Allocator) void {
	self.inputs.deinit(allocator);
	self.macros.deinit();
}

/// Interpret arguments, assuming they have a correct format, and preprocess
/// all input files into their respective outputs.
pub fn run(self: *Self, allocator: Allocator, args: [][:0]u8) !void {
	var expecting = ExpectationStatus.nothing;

	// Don't log anything if preprocessing to stdout to avoid mixing with the file
	// content.
	self.verbose = a.contains_str(args, "-v") and a.contains_str(args, "-o");

	for (args[1..]) |arg| {
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
		else switch (expecting) {
			.output => {
				var file = std.fs.cwd().createFile(arg, .{}) catch {
					a.errtag();
					a.errln("Could not create output file '{s}'!", .{arg});
					return E;
				};
				defer file.close();

				var writer_buf: [1024]u8 = undefined;
				var writer = file.writer(&writer_buf);

				try self.preprocess(allocator, &writer);
				self.inputs.clearRetainingCapacity();
				expecting = .nothing;
				continue;
			},
			.prefix => {
				self.prefix = arg;
				expecting = .nothing;
				continue;
			},
			else => {
				// Input file
				try self.validate_input(allocator, arg);
				try self.inputs.append(allocator, arg);
			}
		}
	}

	if (self.inputs.items.len > 0) try self.preprocess(allocator, &a.stdout);
}

/// Check whether the input file lacks any m5 syntax errors.
fn validate_input(self: *Self, allocator: Allocator, input: []const u8) !void {
	var file = std.fs.cwd().openFile(input, .{ .mode = .read_only }) catch {
		a.errtag();
		a.errln("Could not open input file '{s}'!", .{input});
		return E;
	};
	defer file.close();

	var reader_buf: [1024]u8 = undefined;
	var reader = file.reader(&reader_buf);

	var allocating = Allocating.init(allocator);
	defer allocating.deinit();

	var linenr: usize = 1;
	var scope: usize = 0;

	while (reader.interface.streamDelimiterEnding(&allocating.writer, '\n') catch 0 > 0) : ({
		allocating.clearRetainingCapacity();
		reader.interface.toss(@intFromBool(reader.interface.seek < reader.interface.end)); // skip newline
		linenr += 1;
	}) {
		const line = allocating.written();
		if (!a.startswith(line, self.prefix)) continue;

		const line_wo_prefix = blk: {
			const wo_leading_whitespace = a.trimleft(line, " \t");
			const prefix_skipped = wo_leading_whitespace[self.prefix.len..];
			break :blk a.trimleft(prefix_skipped, " \t");
		};
		if (a.startswith(line_wo_prefix, "if")) {
			scope += 1;
			const condition = line_wo_prefix["if".len..];
			try parser.validate(condition, input, linenr);
		}
		else if (a.startswith(line_wo_prefix, "elif")) {
			if (scope == 0) {
				a.errtag();
				a.errln(
					"{s}, line {d}: There can be no elif without an if clause prior!",
					.{input, linenr}
				);
				return E;
			}
			const condition = line_wo_prefix["elif".len..];
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
			// TODO FINAL TEST
			const first_word = blk: {
				const space_i = std.mem.indexOfScalar(u8, line_wo_prefix, ' ')
					orelse line_wo_prefix.len;
				break :blk line_wo_prefix[0..space_i];
			};
			a.errtag();
			a.errln(
				\\{s}, line {d}: Invalid keyword '{s}'!
				\\Should be 'if', 'elif' or 'end'"
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

fn preprocess(self: *Self, allocator: Allocator, writer: *File.Writer) !void {
	for (self.inputs.items) |input| {
		var file = try std.fs.cwd().openFile(input, .{ .mode = .read_only });
		defer file.close();

		var reader_buf: [1024]u8 = undefined;
		var reader = file.reader(&reader_buf);

		var allocating = Allocating.init(allocator);
		defer allocating.deinit();

		try self.read_lines(&allocating, &reader, writer);
		// TODO FINAL TEST
		if (self.verbose) a.println("Preprocessed {s}!", .{input});
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
		reader.interface.streamDelimiter(&allocating.writer, '\n') catch null
	) |_| : ({
		allocating.clearRetainingCapacity();
		reader.interface.toss(1); // skip newline
		linenr += 1;
	}) {
		const line: []u8 = allocating.written();
		const trimmed: []const u8 = a.trimleft(line, " \t");

		if (!a.startswith(trimmed, self.prefix)) {
			if (write_line == .yes) try writer.interface.print("{s}\n", .{line});
			continue;
		}

		const condition_line = a.trimleft(trimmed[self.prefix.len..], " \t");
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
		else if (a.startswith(condition_line, "elif")) {
			if (write_line != .yes) continue;
			write_line = if (write_line != .no) .ignore
				else switch (parser.parse(condition_line["elif".len..], &self.macros)) {
					true => .yes,
					false => .no
				};
		}
		else if (a.startswith(condition_line, "end")) {
			if (ignore_scopes == 0) write_line = .yes
			else ignore_scopes -= 1;
		}
	}
}
