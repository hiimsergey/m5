const std = @import("std");
const a = @import("alias.zig");
const arguments = @import("arguments.zig");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;
const M5Error = @import("error.zig").M5Error;
const StringHashMap = std.StringHashMap;
const StringList = std.ArrayList([]const u8);
const Writer = std.fs.File.Writer;

const Self = @This();

allocator: Allocator,
inputs: StringList,
macros: StringHashMap([]const u8),
prefix: []const u8,
verbose: bool, // TODO IMPLEMENT

pub fn init(allocator: Allocator) !Self {
	return .{
		.allocator = allocator,
		.inputs = try StringList.initCapacity(allocator, 2),
		.macros = StringHashMap([]const u8).init(allocator),
		.prefix = "",
		.verbose = false
	};
}

pub fn run(self: *Self, allocator: Allocator, args: [][:0]u8) !void {
	const cwd = std.fs.cwd();
	var output_to_file: bool = undefined;

	if (a.contains_str(args, "-v")) self.verbose = true;

	for (args[1..], 1..) |arg, i| {
		self.clear();
		output_to_file = false;

		// Probably the -v flag
		if (arg[0] == '-') {
			continue;
		}
		else if (a.startswith(arg, "-D")) {
			const glued_arg_len = arguments.GLUED[0].len;
			try self.macros.put(arg[glued_arg_len..], "");
		}
		else if (a.startswith(arg, "-U")) {
			const glued_arg_len = arguments.GLUED[0].len;
			_ = self.macros.remove(arg[glued_arg_len..]);
		}
		else if (a.eql(arg, "-p")) {
			self.prefix = args[i + 1];
		}
		else if (a.eql(arg, "-o")) {
			output_to_file = true;

			var file = try cwd.openFile(args[i + 1], .{ .mode = .write_only });
			defer file.close();

			var writer_buf: [1024]u8 = undefined;
			var writer = file.writer(&writer_buf);

			try self.validate_inputs(allocator);
			try self.preprocess(allocator, &writer);
		}
		else {
			// Input file
			try self.inputs.append(allocator, arg);
		}
	}

	if (output_to_file) return;
	try self.validate_inputs(allocator);
	
	try self.preprocess(allocator, &a.stdout);
}

fn clear(self: *Self) void {
	self.inputs.shrinkRetainingCapacity(0);
	self.macros.clearRetainingCapacity();
}

fn preprocess(self: *Self, allocator: Allocator, writer: *Writer) !void {
	var cwd = std.fs.cwd();

	for (self.inputs.items) |input| {
		var file = try cwd.openFile(input, .{ .mode = .read_only });
		defer file.close();

		var reader_buf: [1024]u8 = undefined;
		var reader = file.reader(&reader_buf);

		var allocating = std.Io.Writer.Allocating.init(allocator);
		defer allocating.deinit();

		var cur_condition = false;

		while (reader.interface.streamDelimiter(&allocating.writer, '\n') catch null) |_| {
			const line = allocating.written();
			defer {
				allocating.clearRetainingCapacity();
				reader.interface.toss(1); // skip newline
			}

			if (!a.startswith(line, self.prefix)) {
				if (!cur_condition) continue;
				try writer.interface.writeAll(line);
			}

			const line_wo_prefix = a.trimleft(line[self.prefix.len..], " \t");
			if (a.startswith(line_wo_prefix, "if") or
				a.startswith(line_wo_prefix, "elif")) {
				const condition = line_wo_prefix["if".len..];
				cur_condition = try parser.parse(condition, &self.macros);
			}
			else if (a.startswith(line_wo_prefix, "end")) {
				cur_condition = false;
			}
		}
	}

	self.inputs.clearRetainingCapacity();
	try writer.interface.flush();
}

fn validate_inputs(self: *Self, allocator: Allocator) !void {
	var cwd = std.fs.cwd();

	for (self.inputs.items) |input| {
		var awaiting_end = false;

		var file = try cwd.openFile(input, .{ .mode = .read_only });
		defer file.close();

		var reader_buf: [1024]u8 = undefined;
		var reader = file.reader(&reader_buf);

		var allocating = std.Io.Writer.Allocating.init(allocator);
		defer allocating.deinit();

		while (reader.interface.streamDelimiter(&allocating.writer, '\n') catch null) |_| {
			const line = allocating.written();
			defer {
				allocating.clearRetainingCapacity();
				reader.interface.toss(1); // skip newline
			}
			
			if (!a.startswith(line, self.prefix)) continue;

			const line_wo_prefix = a.trimleft(line[self.prefix.len..], " \t");
			if (a.startswith(line_wo_prefix, "if")) {
				awaiting_end = true;

				const condition = line_wo_prefix["if".len..];
				try parser.validate(condition);
			}
			else if (a.startswith(line_wo_prefix, "elif")) {
				if (!awaiting_end) return M5Error.InvalidKeywordSyntax;
				const condition = line_wo_prefix["elif".len..];
				try parser.validate(condition);
			}
			else if (a.startswith(line_wo_prefix, "end")) {
				if (!awaiting_end) return M5Error.InvalidKeywordSyntax;
				awaiting_end = false;
			}
		}
	}
}

pub fn deinit(self: *Self, allocator: Allocator) void {
	self.inputs.deinit(allocator);
	self.macros.deinit();
}
