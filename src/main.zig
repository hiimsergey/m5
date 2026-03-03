// TODO
// variables are not "0" by default but undefined
// expression containing these variables are automatically false
// keyword: assert <expr> if expr is false, results in error
// arguments: lt {-p:prefix {(-d:key(=val)) {input}}+ -o output }
// support -- as output that lets you use the file "-" as output
// ^ means, ExpectationStatus.output gets delayed
// the output-first notation allows having nothing as prefix
// \; is probably the termination character
//
// lt out.1 
//
const std = @import("std");

const Allocator = std.mem.Allocator;
const AllocatorWrapper = @import("AllocatorWrapper.zig");
const ArgIterator = std.process.ArgIterator;
const File = std.fs.File;

const Context = struct {
	const TerminationStatus = enum(u8) {ok, need_help, user_error, system_error};

	term_status: TerminationStatus = .ok,
	batch_nr: u32 = 1,

	prefix: []const u8 = "",
	macros: std.StringHashMap([]const u8),

	fn init(gpa: Allocator) Context {
		return .{
			.macros = std.StringHashMap([]const u8).init(gpa)
		};
	}

	fn deinit(self: *Context) void {
		self.macros.deinit();
	}

	/// Clears batch-specific data. Increments batch number
	fn clear(self: *Context) void {
		self.batch_nr += 1;
		self.prefix = "";
		self.macros.clearRetainingCapacity();
	}
};

// TODO make error tag bold
const error_tag = "\x1b[31merror: ";
const style_reset = "\x1b[0m\n";
const system_error_code = 71;
const help_text =
	\\lt - a simple text file processor
	\\by Sergey Lavrent (https://github.com/hiimsergey/lt)
	\\v0.1.1   GPL-3.0 license
	\\
	\\TODO
	\\
;

const stdout_file = std.fs.File.stdout();
var stdout_buf: [1024]u8 = undefined;
var stdout_wrapper = stdout_file.writer(&stdout_buf);
const stdout = &stdout_wrapper.interface;

var stderr_buf: [64]u8 = undefined;
var stderr_wrapper = std.fs.File.stderr().writer(&stderr_buf);
const stderr = &stderr_wrapper.interface;

fn err(comptime fmt: []const u8, args: anytype) void {
	stderr.print(error_tag, .{}) catch {};
	stderr.print(fmt ++ "\n", args) catch {};
	stderr.print(style_reset, .{}) catch {};
}

pub fn main() u8 {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();
	const gpa = aw.allocator(std.heap.smp_allocator);

	var args = std.process.argsWithAllocator(gpa) catch return system_error_code;
	defer args.deinit();

	_ = args.skip();

	var ctx = Context.init(gpa);
	defer ctx.deinit();

	batches: while (true) : (ctx.clear()) {
		const output_path: []const u8, const output: File =
			outputPathAndFileFromArgs(&args, &ctx) orelse break :batches;
		defer output.close();
		_ = output_path;

		while (args.next()) |arg| {
			switch (arg[0]) {
				';' => continue :batches,
				'-' => {
					// TODO NOW
					// validate flag; run it
				},
				else => {
					// run+validate file
				}
			}
		} else break :batches;
	}

	switch (ctx.term_status) {
		.ok => return 0,
		.need_help => {
			stderr.print(help_text, .{}) catch {};
			stderr.flush() catch {};
			return 1;
		},
		.user_error => {
			stderr.flush() catch {};
			return 1;
		},
		.system_error => {
			stderr.flush() catch {};
			return system_error_code;
		}
	}
}

// TODO FINAL CONSIDER inlining
/// Returns the path and `std.fs.File` instance of the output file from the first
/// args.
/// Handles the -- escape sequence.
/// On error, logs, alters `ctx.term_status` and returns null.
fn outputPathAndFileFromArgs(args: *ArgIterator, ctx: *Context)
?struct {[]const u8, File} {
	const arg = args.next() orelse return null;
	switch (arg[0]) {
		';' => {
			err("At least one output and one input must be given!", .{});
			ctx.term_status = .user_error;
			return null;
		},
		'-' => {
			if (arg.len == 1) return .{"[stdout]", stdout_file}
			else if (arg[1] == '-') {
				const path = args.next() orelse {
					err("Expected argument after escape sequence '--'!", .{});
					ctx.term_status = .user_error;
					return null;
				};
				const file = std.fs.cwd().openFile(path, .{ .mode = .write_only })
				catch {
					err("Failed to open output file!", .{});
					ctx.term_status = .system_error;
					return null;
				};
				return .{path, file};
			}
			else {
				if (std.mem.eql(u8, arg[1..], "-help")) {
					ctx.term_status = .need_help;
					return null;
				}
				err("Expected path to output file, got flag '{s}'!", .{arg});
				ctx.term_status = .user_error;
				return null;
			}
		},
		else => {
			const file = std.fs.cwd().openFile(arg, .{ .mode = .write_only })
			catch {
				err("Failed to open output file!", .{});
				ctx.term_status = .system_error;
				return null;
			};
			ctx.term_status = .ok;
			return .{arg, file};
		}
	}
	unreachable;
}
