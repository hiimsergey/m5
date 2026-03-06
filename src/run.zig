// TODO ALL REWRITE

const root = @import("root");
const std = @import("std");

const Context = root.Context;

const err = root.err;

// TODO CONSIDER return u8
pub fn withContext(ctx: *const Context) !void {
	// TODO NOW before calling withFile, output file should be confirmed to be working
	for (ctx.input_list) |path| {
		const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch {
			err("'{s}': Failed to open input file! Not proceeding.", .{path});
			return error.E;
		};
		defer file.close();
	}
}

pub fn withFile(file: std.fs.File, ctx: *const Context) !void {
	_ = file;
	_ = ctx;
}
