const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // CLI / node
    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cli = b.addExecutable(.{
        .name = "zizz",
        .root_module = cli_mod,
    });
    b.installArtifact(cli);

    // GUI wallet
    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3,
    });

    const gui_mod = b.createModule(.{
        .root_source_file = b.path("src/wallet_gui.zig"),
        .target = target,
        .optimize = optimize,
    });
    gui_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    gui_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));

    const gui = b.addExecutable(.{
        .name = "zizz-wallet",
        .root_module = gui_mod,
    });
    if (target.result.os.tag == .windows) {
        gui.subsystem = .windows;
    }
    b.installArtifact(gui);

    const run_gui = b.addRunArtifact(gui);
    const gui_step = b.step("wallet", "Run the ZiZZ GUI wallet");
    gui_step.dependOn(&run_gui.step);
    // Webview wallet
    const webui_dep = b.dependency("zig_webui", .{
        .target = target,
        .optimize = optimize,
    });
    const web_mod = b.createModule(.{
        .root_source_file = b.path("src/wallet_web.zig"),
        .target = target,
        .optimize = optimize,
    });
    web_mod.addImport("webui", webui_dep.module("webui"));
    const web = b.addExecutable(.{
        .name = "zizz-web",
        .root_module = web_mod,
    });
    if (target.result.os.tag == .windows) {
        web.subsystem = .windows;
    }
    b.installArtifact(web);

}
