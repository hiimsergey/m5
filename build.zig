const Build = @import("std").Build;

// Latest Zig version as of writing this: 0.15.1
pub fn build(b: *Build) void {
	// Options
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	// Executable declaration
	const exe = b.addExecutable(.{
		.name = "m5",
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize
	});

	exe.linkLibC(); // Needed for `std.heap.c_allocator`

	// Actual installation
	b.installArtifact(exe);
}
