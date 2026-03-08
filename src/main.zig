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

// TODO new arg table
// --help help
// -safe exit with error if encountering undefined variable, treat it as false otherwise
//     ^ TODO give shoutout
// -verbose verbose
// -o output
// -p prefix
// -d define
// -flag invalid flag
// input
//
// argtable layout
// $0
// input
// prefix
//
// stack layout
// safe
// verbose
// input slice
// defines

// TODO prevent file-defined macros to leak into other files
// TODO use tagged unions int/string
// TODO decide between arraylist and arenaallocator for macro strings

const std = @import("std");
const log = @import("log.zig");

const AllocatorWrapper = @import("AllocatorWrapper.zig");
const Context = @import("Context.zig");
const File = std.fs.File;
pub const MacroInt = Context.MacroInt;

const help_text =
	\\lt - a simple text file processor
	\\by Sergey Lavrent (https://github.com/hiimsergey/lt)
	\\v0.1.1   GPL-3.0 license
	\\
	\\TODO
	\\
;

const stdout_file = File.stdout();
var stdout_buf: [1024]u8 = undefined;
var stdout_wrapper = stdout_file.writer(&stdout_buf);
const stdout = &stdout_wrapper.interface;

pub fn main() u8 {
	realMain() catch |e| return switch (e) {
		error.Generic => 1,
		error.SystemError => 71
	};
	return 0;
}

fn realMain() error{Generic, SystemError}!void {
	defer log.stderr.flush() catch {};

	var aw = AllocatorWrapper.init();
	defer aw.deinit();
	const gpa = aw.allocator(std.heap.smp_allocator);

	var args = std.process.argsWithAllocator(gpa) catch return error.SystemError;
	defer args.deinit();
	_ = args.skip(); // Skips executable name

	var ctx = Context.init(gpa);
	defer ctx.deinit();

	const stdin = std.fs.File.stdin();
	const input_from_pipe: bool = !stdin.isTty();
	const cwd = std.fs.cwd();

	while (args.next()) |arg| {
		if (arg[0] != '-') {
			if (input_from_pipe) {
				log.errWithHelp(
					"You can either take input from pipe or from positional " ++
					"argument, not both!",
					.{});
				return error.Generic;
			}
			ctx.input = cwd.openFile(arg, .{ .mode = .read_only }) catch {
				// TODO switch |e|
				log.err("Failed to open input '{s}'!", .{arg});
				return error.Generic;
			};
		}
		else if (std.mem.eql(u8, arg[1..], "-help")) {
			log.stderr.print(help_text, .{}) catch {};
			return error.Generic;
		}
		else if (std.mem.eql(u8, arg[1..], "-safe")) {
			ctx.flags.safe = true;
		}
		else if (std.mem.eql(u8, arg[1..], "-verbose")) {
			ctx.flags.verbose = true;
		}
		else if (std.mem.startsWith(u8, arg[1..], "o:")) {
			const output_path = arg["-o:".len..];
			ctx.output = cwd.openFile(output_path, .{ .mode = .write_only }) catch {
				// TODO switch |e|
				log.err("Failed to open output '{s}'!", .{output_path});
				return error.Generic;
			};
		}
		else if (std.mem.startsWith(u8, arg[1..], "p:")) {
			const body = arg["-p:".len..];
			if (body.len > ctx._prefix_buf.len) {
				log.err(
					"Prefix must be at most {d} characters (bytes) long!",
					.{ctx._prefix_buf.len});
				return error.Generic;
			}
			@memcpy(ctx._prefix_buf[0..body.len], body);
			ctx.prefix = ctx._prefix_buf[0..body.len];
		}
		else if (std.mem.startsWith(u8, arg[1..], "d:")) {
			const key: []const u8, const value: MacroInt = try readDefinition(arg);
			ctx.macros.put(key, value) catch return error.SystemError;
		}
		else {
			log.errWithHelp("Invalid flag '{s}'!", .{arg});
			return error.Generic;
		}
	}

	if (ctx.input == null) {
		if (!input_from_pipe) {
			log.errWithHelp(
				"Input must be given as a positional argument or through piping!",
				.{});
			return error.Generic;
		}
		ctx.input = stdin;
	}
	if (ctx.prefix == null) {
		log.errWithHelp("Prefix must be given with the -p flag!", .{});
		return error.Generic;
	}

	ctx.output = ctx.output orelse std.fs.File.stdout();
	try ctx.run(gpa);
}

/// Logs on error.
fn readDefinition(flag: []const u8) error{Generic}!struct {[]const u8, MacroInt} {
	// '=' is also banned, of course, but is guaranteed to not appear in
	// the key string.
	const banned_chars = "+-&|!<>() \t";
	const definition = flag["-d:".len..];

	const validateKey = struct {
		/// Returns an error and logs if `buf` can't be a valid key.
		fn f(buf: []const u8) error{Generic}!void {
			if (buf.len == 0) {
				log.err("You can't define a macro with an empty name!", .{});
				return error.Generic;
			}
			for (buf) |c| if (std.mem.containsAtLeastScalar(u8, banned_chars, 1, c)) {
				log.err("Key '{s}' contains forbidden character '{c}'!", .{buf, c});
				return error.Generic;
			};
			if (isNumber(buf)) {
				log.err("Keys can't be numbers!", .{});
				return error.Generic;
			}
		}

		fn isNumber(buf: []const u8) bool {
			for (buf) |c| switch (c) {
				'0'...'9', '_' => continue,
				else => return false
			};
			return true;
		}
	}.f;

	const key_cand: []const u8, const value: MacroInt = kv: {
		const eq_index = std.mem.indexOfScalar(u8, definition, '=') orelse
			break :kv .{definition, 1};

		const key_cand = definition[0..eq_index];
		const value_buf: []const u8 = definition[eq_index + 1..];
		const value = std.fmt.parseInt(MacroInt, value_buf, 10) catch |e| switch (e) {
			error.Overflow => {
				log.err(
					\\The number {s} is not representable!"
					\\Only numbers from {d} to {d} are supported!
					, .{value_buf, std.math.minInt(MacroInt), std.math.maxInt(MacroInt)}
				);
				return error.Generic;
			},
			error.InvalidCharacter => {
				log.err("The value '{s}' is not a valid number!", .{value_buf});
				return error.Generic;
			}
		};

		break :kv .{key_cand, value};
	};

	try validateKey(key_cand);
	return .{key_cand, value};
}

// TODO TEST non-ascii define names, like cyrillic
