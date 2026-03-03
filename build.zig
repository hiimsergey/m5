const Build = @import("std").Build;

// Latest Zig version as of writing this: 0.15.1
pub fn build(b: *Build) void {
	// Options
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	// Executable declaration
	const exe = b.addExecutable(.{
		.name = "lt",
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.target = target,
			.optimize = optimize
		})
	});

	// Actual installation
	b.installArtifact(exe);
}
