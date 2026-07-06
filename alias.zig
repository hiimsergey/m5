const std = @import("std");
/// Standard function wrappers.
const a = @This();

/// Wrapper around std.mem.startsWith.
pub fn startsWith(haystack: []const u8, needle: []const u8) bool {
	return std.mem.startsWith(u8, haystack, needle);
}

/// Wrapper around std.mem.trim
pub fn trimW(buf: []const u8) []const u8 {
	return std.mem.trim(u8, buf, " \t");
}

/// Wrapper around std.mem.trimStart
pub fn trimWStart(buf: []const u8) []const u8 {
	return std.mem.trimStart(u8, buf, " \t");
}

/// Wrapper around std.mem.trimEnd
pub fn trimWEnd(buf: []const u8) []const u8 {
	return std.mem.trimEnd(u8, buf, " \t");
}
