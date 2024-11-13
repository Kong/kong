"""
Global variables
"""

def _load_bindings_impl(ctx):
    root = "/".join(ctx.execute(["pwd"]).stdout.split("/")[:-1])

    ctx.file("BUILD.bazel", "")
    ctx.file("variables.bzl", "INTERNAL_ROOT = \"%s\"\n" % root)

load_bindings = repository_rule(
    implementation = _load_bindings_impl,
)
