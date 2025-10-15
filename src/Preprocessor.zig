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

fn clear(self: *Self) void {
	self.inputs.shrinkRetainingCapacity(0);
	self.macros.clearRetainingCapacity();
}

pub fn run(self: *Self, allocator: Allocator, args: [][:0]u8) !void {
	var output_to_file: bool = undefined;

	self.verbose = a.contains_str(args, "-v") and a.contains_str(args, "-o");

	for (args[1..], 1..) |arg, i| {
		self.clear();
		output_to_file = false;

		// Gotta be the -v flag
		if (arg[0] == '-') continue
		else if (a.startswith(arg, "-D")) {
			try self.macros.put(arg["-D".len..], "");
		}
		else if (a.eql(arg, "-p")) {
			self.prefix = args[i + 1];
		}
		else if (a.eql(arg, "-o")) {
			output_to_file = true;

			var file = try std.fs.cwd().openFile(args[i + 1], .{ .mode = .write_only });
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

			// TODO leading whitespace should be ignored
			if (!a.startswith(line, self.prefix)) {
				if (write_line) try writer.interface.writeAll(line);
				continue;
			}

			const line_wo_prefix = a.trimleft(line[self.prefix.len..], " \t");
			inline for ([_][]const u8{"if", "elif"}) |keyword| {
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

			a.errln(
				"{s}: line {d}: Invalid keyword! Should be 'if', 'elif' or 'end'",
				.{input, linenr}
			);
			return M5Error.InvalidKeywordSyntax;
		}

		if (self.verbose) a.println("Preprocessed {s}!\n", .{input});
	}

	self.inputs.clearRetainingCapacity();
	try writer.interface.flush();
}

fn validate_inputs(self: *Self, allocator: Allocator) !void {
	for (self.inputs.items) |input| {
		var awaiting_end = false;

		var file = try std.fs.cwd().openFile(input, .{ .mode = .read_only });
		defer file.close();

		var reader_buf: [1024]u8 = undefined;
		var reader = file.reader(&reader_buf);

		var allocating = std.Io.Writer.Allocating.init(allocator);
		defer allocating.deinit();

		while (reader.interface.streamDelimiter(&allocating.writer, '\n') catch null)
		|_| {
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
