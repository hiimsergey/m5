const std = @import("std");

pub fn contains_str(haystack: []const []const u8, needle: []const u8) bool {
	for (haystack) |hay| if (eql(hay, needle)) return true;
	return false;
}

pub fn eql(a: []const u8, b: []const u8) bool {
	return std.mem.eql(u8, a, b);
}

pub fn startswith(a: []const u8, b: []const u8) bool {
	return std.mem.startsWith(u8, a, b);
}

pub fn trimleft(slice: []const u8, trim: []const u8) []const u8 {
	return std.mem.trimLeft(u8, slice, trim);
}
