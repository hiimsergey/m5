const Build = @import("std").Build;

// Latest Zig version as of writing this: 0.16.0
pub fn build(b: *Build) void {
	// Options
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	// Executable declaration
	const exe = b.addExecutable(.{
		.name = "m5",
		.root_module = b.createModule(.{
			.root_source_file = b.path("main.zig"),
			.target = target,
			.optimize = optimize
		})
	});

	// Actual installation
	b.installArtifact(exe);
}
