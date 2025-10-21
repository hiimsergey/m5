const std = @import("std");
const a = @import("alias.zig");
const arguments = @import("arguments.zig");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const File = std.fs.File;
const M5Error = @import("error.zig").M5Error;
const StringHashMap = std.StringHashMap;

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

fn clear(self: *Self) void {
	self.inputs.clearRetainingCapacity();
	self.macros.clearRetainingCapacity();
}

pub fn run(self: *Self, allocator: Allocator, args: [][:0]u8) !void {
	const ExpectationStatus = enum(u8) {none, output, prefix};
	var expecting = ExpectationStatus.none;

	self.verbose = a.contains_str(args, "-v") and a.contains_str(args, "-o");

	for (args[1..]) |arg| {
		if (a.startswith(arg, "-D")) {
			try self.macros.put(arg["-D".len..], "");
		}
		else if (a.eql(arg, "-p")) {
			expecting = .prefix;
		}
		else if (a.eql(arg, "-o")) {
			expecting = .output;
		}
		else if (arg[0] == '-') continue // gotta be the -v flag
		else {
			if (expecting == .output) {
				var file = try std.fs.cwd().openFile(arg, .{ .mode = .write_only });
				defer file.close();

				var writer_buf: [1024]u8 = undefined;
				var writer = file.writer(&writer_buf);

				try self.preprocess(allocator, &writer);
				self.clear();
				expecting = .none;
				continue;
			}
			if (expecting == .refix) {
				self.prefix = arg;
				expecting = .none;
				continue;
			}

			// Input file
			try self.validate_input(allocator, arg);
			try self.inputs.append(allocator, arg);
		}
	}

	if (self.inputs.items.len > 0) try self.preprocess(allocator, &a.stdout);
}

fn validate_input(self: *Self, allocator: Allocator, input: []const u8) !void {
	var file = std.fs.cwd().openFile(input, .{ .mode = .read_only }) catch {
		a.errln("Could not open input file '{s}'!", .{input});
		return M5Error.BadArgs;
	};
	defer file.close();

	var reader_buf: [1024]u8 = undefined;
	var reader = file.reader(&reader_buf);

	var allocating = std.Io.Writer.Allocating.init(allocator);
	defer allocating.deinit();

	var expecting_block_end = false;

	var linenr: usize = 1;
	while (reader.interface.streamDelimiter(&allocating.writer, '\n') catch null)
	|_| : ({
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
			expecting_block_end = true;
			const condition = line_wo_prefix["if".len..];
			try parser.validate(condition, input, linenr);
		}
		else if (a.startswith(line_wo_prefix, "elif")) {
			if (!expecting_block_end) return M5Error.InvalidKeywordSyntax;
			const condition = line_wo_prefix["elif".len..];
			try parser.validate(condition, input, linenr);
		}
		else if (a.startswith(line_wo_prefix, "end")) {
			if (!expecting_block_end) return M5Error.InvalidKeywordSyntax;
			expecting_block_end = false;
		}
	}
}

fn preprocess(self: *Self, allocator: Allocator, writer: *File.Writer) !void {
	var write_line = true;

	for (self.inputs.items) |input| {
		var file = try std.fs.cwd().openFile(input, .{ .mode = .read_only });
		defer file.close();

		var reader_buf: [1024]u8 = undefined;
		var reader = file.reader(&reader_buf);

		var allocating = std.Io.Writer.Allocating.init(allocator);
		defer allocating.deinit();

		var linenr: usize = 1;
		lines: while (
			reader.interface.streamDelimiter(&allocating.writer, '\n') catch null
		) |_| : ({
			allocating.clearRetainingCapacity();
			reader.interface.toss(1); // skip newline
			linenr += 1;
		}) {
			const line: []u8 = allocating.written();
			const trimmed: []const u8 = a.trimleft(line, " \t");

			if (!a.startswith(trimmed, self.prefix)) {
				if (write_line) try writer.interface.print("{s}\n", .{line});
				continue;
			}

			const line_wo_prefix = a.trimleft(trimmed[self.prefix.len..], " \t");
			inline for (.{"if", "elif"}) |keyword| {
				if (a.startswith(line_wo_prefix, keyword)) {
					const condition = line_wo_prefix[keyword.len..];
					write_line = parser.parse(condition, &self.macros);
					continue :lines;
				}
			}
			if (a.startswith(line_wo_prefix, "end")) {
				write_line = true;
				continue;
			}

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

		// TODO FINAL TEST
		if (self.verbose) a.println("Preprocessed {s}!\n", .{input});
	}

	try writer.interface.flush();
}
