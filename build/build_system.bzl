"""
Load this file for all Kong-specific build macros
and rules that you'd like to use in your BUILD files.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

# A genrule variant that can output a directory.
def _kong_directory_genrule_impl(ctx):
    tree = ctx.actions.declare_directory(ctx.attr.output_dir)
    env = dicts.add(KONG_VAR, ctx.configuration.default_shell_env, {
        "GENRULE_OUTPUT_DIR": tree.path,
    })
    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        tools = ctx.files.tools,
        outputs = [tree],
        command = "mkdir -p " + tree.path + " && " + ctx.expand_location(ctx.attr.cmd),
        env = env,
    )
    return [DefaultInfo(files = depset([tree]))]

kong_directory_genrule = rule(
    implementation = _kong_directory_genrule_impl,
    attrs = {
        "srcs": attr.label_list(),
        "cmd": attr.string(),
        "tools": attr.label_list(),
        "output_dir": attr.string(),
    },
)
