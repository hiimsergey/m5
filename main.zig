const std = @import("std");
const a = @import("alias.zig");
const log = @import("log.zig");

const Init = std.process.Init;
const OpenError = std.Io.File.OpenError;
const Context = @import("Context.zig");
const File = std.Io.File;
const MacroInt = Context.MacroInt;

const help_text =
	\\m5 - a simple conditional line processor
	\\by Sergey Lavrent (https://github.com/hiimsergey/m5)
	\\v0.3.6   GPL-3.0 license
	\\
	\\Usage: m5 [<options>] <input>
	\\
	\\Options:
	\\  --help               print this message
	\\  --safe               exit with error on encountering undefined variable
	\\
	\\  -o:<file>            write result into file
	\\                         if not given, write to stdout
	\\  -p:<text>            set string marking beginning of m5 directive lines
	\\                         must be given
	\\  -d:<key>[=<number>]  define variable with value
	\\                         if value not given, default is 1
	\\
;

pub fn main(init: Init) u8 {
	log.setup(init.io);
	defer log.stderr.flush() catch {};

	realMain(init) catch |e| switch (e) {
		error.User => return 1,
		error.System => {
			log.err("System failure!", .{});
			return 71;
		}
	};
	return 0;
}

pub const validateKey = struct {
	const banned_chars = "=+-*/&|!<>() \t";

	/// Returns an error and logs if `buf` can't be a valid key.
	fn f(buf: []const u8) error{User}!void {
		if (buf.len == 0) {
			log.err("Key may not have empty name!", .{});
			return error.User;
		}
		for (buf) |c| if (std.mem.containsAtLeastScalar(u8, banned_chars, 1, c)) {
			log.err("Key '{s}' contains forbidden character '{c}'!", .{buf, c});
			return error.User;
		};
		if (isNumber(buf)) {
			log.err("Keys can't be numbers!", .{});
			return error.User;
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

// TODO TEST non-ascii define names, like cyrillic
// TODO FINAL ALL TEST log.err* (branch coverage)

fn realMain(init: Init) error{User, System}!void {
	const gpa = init.gpa;
	const io = init.io;

	var args = init.minimal.args.iterateAllocator(gpa) catch return error.System;
	defer args.deinit();
	_ = args.skip(); // Skips executable name

	var ctx = Context.init(gpa);
	defer ctx.deinit(io);

	const stdin = File.stdin();
	const input_from_pipe: bool = input_from_pipe: {
		const isatty: bool = stdin.isTty(io) catch return error.System;
		break :input_from_pipe !isatty;
	};
	const cwd = std.Io.Dir.cwd();

	while (args.next()) |arg| {
		if (arg[0] != '-') {
			ctx.input = cwd.openFile(io, arg, .{ .mode = .read_only }) catch |e| {
				logOpenError(e, arg);
				return error.User;
			};
		}
		else if (std.mem.eql(u8, arg[1..], "-help")) {
			File.stdout().writeStreamingAll(io, help_text) catch {};
			return;
		}
		// When encountering undefined variable, exit with error
		else if (std.mem.eql(u8, arg[1..], "-safe")) {
			// Shoutout to @MrMineDe for forcing me to implement this feature.
			ctx.safe = true;
		}
		else if (a.startsWith(arg[1..], "o:")) {
			const output_path = arg["-o:".len..];
			ctx.output = cwd.createFile(io, output_path, .{}) catch |e| {
				logOpenError(e, arg);
				return error.User;
			};
		}
		else if (a.startsWith(arg[1..], "p:")) {
			const prefix = arg["-p:".len..];
			if (prefix.len > ctx._prefix_buf.len) {
				log.err(
					"Prefix must be at most {d} characters (bytes) long!",
					.{ctx._prefix_buf.len});
				return error.User;
			}
			@memcpy(ctx._prefix_buf[0..prefix.len], prefix);
			ctx.prefix = ctx._prefix_buf[0..prefix.len];
		}
		else if (a.startsWith(arg[1..], "d:")) {
			const key: []const u8, const value: MacroInt = try readDefinition(arg);
			ctx.macros.put(key, value) catch return error.System;
		}
		else {
			log.errWithHelp("Invalid flag '{s}'!", .{arg});
			return error.User;
		}
	}

	if (ctx.input == null) {
		if (!input_from_pipe) {
			log.errWithHelp(
				"Input must be given as a positional argument or through piping!",
				.{});
			return error.User;
		}
		ctx.input = stdin;
	}
	if (ctx.prefix == null) {
		log.errWithHelp("Prefix must be given with the -p flag!", .{});
		return error.User;
	}

	// If no -o flag given, print to stdout.
	ctx.output = ctx.output orelse File.stdout();

	// This is where the fun begins!
	return ctx.run(gpa, io);
}

/// Does proper lgoging on failed file opening.
fn logOpenError(e: OpenError, arg: []const u8) void {
	switch (e) {
		OpenError.FileNotFound => log.err("Input '{s}' does not exist!", .{arg}),
		OpenError.AccessDenied =>
			log.err("Permission to open input '{s}' denied!", .{arg}),
		OpenError.IsDir => log.err("Input '{s}' is not a file but a dir!", .{arg}),
		else => log.err("Failed to open input '{s}'!", .{arg})
	}
}

/// Logs on error.
fn readDefinition(flag: []const u8) error{User}!struct {[]const u8, MacroInt} {
	const definition = flag["-d:".len..];

	const key_cand: []const u8, const value: MacroInt = kv: {
		const eq_index = std.mem.indexOfScalar(u8, definition, '=') orelse
			break :kv .{definition, 1};

		const key_cand = definition[0..eq_index];
		const value_buf: []const u8 = a.trimWEnd(definition[eq_index + 1..]);
		const value = std.fmt.parseInt(MacroInt, value_buf, 10) catch |e| {
			switch (e) {
				error.Overflow => log.err(
					\\Number {s} is not representable!"
					\\Only numbers from {d} to {d} are supported!
					, .{value_buf, std.math.minInt(MacroInt), std.math.maxInt(MacroInt)}
				),
				error.InvalidCharacter => log.err("Value '{s}' is not a valid number!",
					.{value_buf})
			}
			return error.User;
		};

		break :kv .{key_cand, value};
	};

	try validateKey(key_cand);
	return .{key_cand, value};
}

test {
	_ = @import("parser.zig");
	_ = @import("test.zig");
}
