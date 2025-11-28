const std = @import("std");
const a = @import("alias.zig");
const arguments = @import("arguments.zig");
const parser = @import("parser.zig");

const Allocating = std.Io.Writer.Allocating;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const File = std.fs.File;
const M5Error = @import("error.zig").M5Error;
const StringHashMap = std.StringHashMap;


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
	// Token messaging what kind of argument is expected next
	const ExpectationStatus = enum(u8) {nothing, output, prefix};
	const Pair = struct { key: []const u8, value: []const u8 };

	var expecting = ExpectationStatus.nothing;

	// Don't log anything if preprocessing to stdout to avoid mixing with the file
	// content.
	self.verbose = a.contains_str(args, "-v") and a.contains_str(args, "-o");

	for (args[1..]) |arg| {
		if (a.startswith(arg, "-D")) {
			const definition = arg["-D".len..];
			const pair: Pair = blk: {
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
			if (expecting == .output) {
				var file = std.fs.cwd().createFile(arg, .{}) catch {
					a.errln("Could not create output file '{s}'!", .{arg});
					return M5Error.System;
				};
				defer file.close();

				var writer_buf: [1024]u8 = undefined;
				var writer = file.writer(&writer_buf);

				try self.preprocess(allocator, &writer);
				self.inputs.clearRetainingCapacity();
				expecting = .nothing;
				continue;
			}
			if (expecting == .prefix) {
				self.prefix = arg;
				expecting = .nothing;
				continue;
			}

			// Input file
			try self.validate_input(allocator, arg);
			try self.inputs.append(allocator, arg);
		}
	}

	if (self.inputs.items.len > 0) try self.preprocess(allocator, &a.stdout);
}

/// Check whether the input file lacks any m5 syntax errors.
fn validate_input(self: *Self, allocator: Allocator, input: []const u8) !void {
	var file = std.fs.cwd().openFile(input, .{ .mode = .read_only }) catch {
		a.errln("Could not open input file '{s}'!", .{input});
		return M5Error.BadArgs;
	};
	defer file.close();

	var reader_buf: [1024]u8 = undefined;
	var reader = file.reader(&reader_buf);

	var allocating = Allocating.init(allocator);
	defer allocating.deinit();

	var nesting: u32 = 0;
	var linenr: u32 = 1;

	while (reader.interface.streamDelimiter(&allocating.writer, '\n') catch null) |_| : ({
		allocating.clearRetainingCapacity();
		reader.interface.toss(1); // skip newline
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
			nesting += 1;
			const condition = line_wo_prefix["if".len..];
			try parser.validate(condition, input, linenr);
		}
		else if (a.startswith(line_wo_prefix, "elif")) {
			if (nesting == 0) return M5Error.InvalidBlockSyntax;
			const condition = line_wo_prefix["elif".len..];
			try parser.validate(condition, input, linenr);
		}
		else if (a.startswith(line_wo_prefix, "end")) {
			if (nesting == 0) return M5Error.InvalidBlockSyntax;
			nesting -= 1;
		}
		else {
			// TODO FINAL TEST
			const first_word = blk: {
				const space_i = std.mem.indexOfScalar(u8, line_wo_prefix, ' ')
					orelse line_wo_prefix.len;
				break :blk line_wo_prefix[0..space_i];
			};
			a.errln(
				\\{s}: line {d}: Invalid keyword '{s}'!
				\\Should be 'if', 'elif' or 'end'"
				, .{input, linenr, first_word}
			);
			return M5Error.InvalidKeywordSyntax;
		}
	}

	if (nesting == 0) return;
	a.errln("{s}: line {d}: If clause lacks end keyword!", .{input, linenr});
	return M5Error.InvalidBlockSyntax;
}

fn preprocess(self: *Self, allocator: Allocator, writer: *File.Writer) !void {
	for (self.inputs.items) |input| {
		var file = try std.fs.cwd().openFile(input, .{ .mode = .read_only });
		defer file.close();

		var reader_buf: [1024]u8 = undefined;
		var reader = file.reader(&reader_buf);

		var allocating = Allocating.init(allocator);
		defer allocating.deinit();

		var linenr: usize = 1;
		try self.read_lines(input, &allocating, &reader, writer, .yes, &linenr);

		// TODO FINAL TEST
		if (self.verbose) a.println("Preprocessed {s}!", .{input});
	}
	try writer.interface.flush();
}

fn read_lines(
	self: *Self,
	input: []const u8, allocating: *Allocating,
	reader: *File.Reader, writer: *File.Writer,
	wl: WriteLine, linenr: *usize
) !void {
	var write_line: WriteLine = wl;

	while (
		reader.interface.streamDelimiter(&allocating.writer, '\n') catch null
	) |_| : ({
		allocating.clearRetainingCapacity();
		reader.interface.toss(1); // skip newline
		linenr.* += 1;
	}) {
		const line: []u8 = allocating.written();
		const trimmed: []const u8 = a.trimleft(line, " \t");

		if (!a.startswith(trimmed, self.prefix)) {
			if (write_line == .yes) try writer.interface.print("{s}\n", .{line});
			continue;
		}

		const line_wo_prefix = a.trimleft(trimmed[self.prefix.len..], " \t");
		if (a.startswith(line_wo_prefix, "if")) {
			const condition = line_wo_prefix["if".len..];
			// TODO NOW
			// handle case where coming from another if
			//
			// wl parse
			// ignore _ -> ignore
			// false ignore
			// false false
			// false true
			// true ignore
			// true false
			// true true
			const new_write_line: WriteLine = switch (
				parser.parse(condition, &self.macros
			)) {
				true => .yes,
				false => .no
			};
			try self.read_lines(input, allocating, reader, writer, new_write_line, linenr);
		}
		// TODO NOW
		// this should fail if there was no if, right?
		if (a.startswith(line_wo_prefix, "elif")) {
			const condition = line_wo_prefix["elif".len..];
			write_line = switch (write_line) {
				.no => switch (parser.parse(condition, &self.macros)) {
					true => .yes,
					false => .no
				},
				else => .ignore
			};
			continue;
		}
		// TODO NOW
		// this function must change .ignore, does it?
		if (a.startswith(line_wo_prefix, "end")) return;
	}

	// TODO NOW MOVE validate_input
	a.errln("{s}: line {d}: If-clause lacks end keyword!", .{input, linenr.*});
	return M5Error.InvalidBlockSyntax;
}
