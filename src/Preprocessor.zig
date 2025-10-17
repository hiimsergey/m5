const std = @import("std");
const a = @import("alias.zig");
const arguments = @import("arguments.zig");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const M5Error = @import("error.zig").M5Error;
const StringHashMap = std.StringHashMap;
const StringList = std.ArrayList([]const u8);

const Self = @This();

inputs: StringList,
macros: StringHashMap([]const u8),
prefix: []const u8,
verbose: bool,

pub fn init(allocator: Allocator) !Self {
	return .{
		.inputs = try StringList.initCapacity(allocator, 2),
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
	var output_to_file = false;
	var expecting_output = false;
	var expecting_prefix = false;

	self.verbose = a.contains_str(args, "-v") and a.contains_str(args, "-o");

	for (args[1..]) |arg| {
		if (a.startswith(arg, "-D")) {
			try self.macros.put(arg["-D".len..], "");
		}
		else if (a.eql(arg, "-p")) {
			expecting_prefix = true;
		}
		else if (a.eql(arg, "-o")) {
			output_to_file = true;
			expecting_output = true;
		}
		else if (arg[0] == '-') continue // gotta be the -v flag
		else {
			if (expecting_output) {
				var file = try std.fs.cwd().openFile(arg, .{ .mode = .write_only });
				defer file.close();

				var writer_buf: [1024]u8 = undefined;
				var writer = file.writer(&writer_buf);

				try self.preprocess(allocator, &writer);
				self.clear();
				output_to_file = false;
				expecting_output = false;
				expecting_prefix = false;
				continue;
			}
			if (expecting_prefix) {
				self.prefix = arg;
				continue;
			}

			// Input file
			try self.validate_input(allocator, arg); // TODO NOW IMPLEMENT
			try self.inputs.append(allocator, arg);
		}
	}

	if (output_to_file) return;
	try self.preprocess(allocator, &a.stdout);
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

	while (reader.interface.streamDelimiter(&allocating.writer, '\n') catch null)
	|_| : ({
		allocating.clearRetainingCapacity();
		reader.interface.toss(1); // skip newline
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
			try parser.validate(condition);
		}
		else if (a.startswith(line_wo_prefix, "elif")) {
			if (!expecting_block_end) return M5Error.InvalidKeywordSyntax;
			const condition = line_wo_prefix["elif".len..];
			try parser.validate(condition);
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
					write_line = try parser.parse(condition, &self.macros);
					continue :lines;
				}
			}
			if (a.startswith(line_wo_prefix, "end")) {
				write_line = true;
				continue;
			}

			// TODO NOW CONSIDER writing invalid keyword itself
			a.errln(
				"{s}: line {d}: Invalid keyword! Should be 'if', 'elif' or 'end'",
				.{input, linenr}
			);
			return M5Error.InvalidKeywordSyntax;
		}

		if (self.verbose) a.println("Preprocessed {s}!\n", .{input});
	}

	try writer.interface.flush();
}
