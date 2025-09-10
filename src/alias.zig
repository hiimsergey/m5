const std = @import("std");

pub inline fn contains(haystack: []const []const u8, needle: []const u8) bool {
	return std.mem.containsAtLeast(u8, @ptrCast(haystack), 1, needle);
}

pub inline fn eql(a: []const u8, b: []const u8) bool {
	return std.mem.eql(u8, a, b);
}

pub inline fn startswith(a: []const u8, b: []const u8) bool {
	return std.mem.startsWith(u8, a, b);
}

pub inline fn trimleft(slice: []const u8, trim: []const u8) []const u8 {
	return std.mem.trimLeft(u8, slice, trim);
}
