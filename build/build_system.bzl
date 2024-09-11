"""
Load this file for all Kong-specific build macros
and rules that you'd like to use in your BUILD files.
"""

load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository", "new_git_repository")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def _kong_genrule_impl(ctx):
    outputs = []
    for f in ctx.attr.outs:
        outputs.append(ctx.actions.declare_file(KONG_VAR["BUILD_NAME"] + "/" + f))

    for f in ctx.attr.out_dirs:
        outputs.append(ctx.actions.declare_directory(KONG_VAR["BUILD_NAME"] + "/" + f))

    env = dict(KONG_VAR)
    env["BUILD_DESTDIR"] = ctx.var["BINDIR"] + "/build/" + env["BUILD_NAME"]

    # XXX: remove the "env" from KONG_VAR which is a list
    env["OPENRESTY_PATCHES"] = ""

    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        tools = ctx.files.tools,
        outputs = outputs,
        command = ctx.expand_location(ctx.attr.cmd),
        env = env,
    )
    return [DefaultInfo(files = depset(outputs))]

kong_genrule = rule(
    implementation = _kong_genrule_impl,
    doc = "A genrule that prefixes output files with BUILD_NAME",
    attrs = {
        "srcs": attr.label_list(),
        "cmd": attr.string(),
        "tools": attr.label_list(),
        "outs": attr.string_list(),
        "out_dirs": attr.string_list(),
    },
)

def _kong_rules_group_impl(ctx):
    return [DefaultInfo(files = depset(ctx.files.propagates))]

kong_rules_group = rule(
    implementation = _kong_rules_group_impl,
    doc = "A rule that can be used as a meta rule that propagates multiple other rules",
    attrs = {
        "propagates": attr.label_list(),
    },
)

_kong_template_attrs = {
    "template": attr.label(
        mandatory = True,
        allow_single_file = True,
    ),
    "output": attr.output(
        mandatory = True,
    ),
    "substitutions": attr.string_dict(),
    "srcs": attr.label_list(allow_files = True, doc = "List of locations to expand the template, in target configuration"),
    "tools": attr.label_list(allow_files = True, cfg = "exec", doc = "List of locations to expand the template, in exec configuration"),
    "is_executable": attr.bool(default = False),
    # hidden attributes
    "_cc_toolchain": attr.label(
        default = "@bazel_tools//tools/cpp:current_cc_toolchain",
    ),
}

def _render_template(ctx, output):
    substitutions = dict(ctx.attr.substitutions)
    for l in ctx.attr.srcs + ctx.attr.tools:
        if OutputGroupInfo in l and "gen_dir" in l[OutputGroupInfo]:  # usualy it's foreign_cc target
            p = l[OutputGroupInfo].gen_dir.to_list()[0].path
        else:  # otherwise it's usually output from gen_rule, file_group etc
            files = l.files.to_list()
            p = files[0].path
            for file in files:  # get the one with shorted path, that will be the directory
                if len(file.path) < len(p):
                    p = file.path
        substitutions["{{%s}}" % l.label] = p

    substitutions["{{CC}}"] = ctx.attr._cc_toolchain[cc_common.CcToolchainInfo].compiler_executable

    # yes, not a typo, use gcc for linker
    substitutions["{{LD}}"] = substitutions["{{CC}}"]
    substitutions["{{build_destdir}}"] = ctx.var["BINDIR"] + "/build/" + KONG_VAR["BUILD_NAME"]

    ctx.actions.expand_template(
        template = ctx.file.template,
        output = output,
        substitutions = substitutions,
        is_executable = ctx.attr.is_executable,
    )

def _kong_template_file_impl(ctx):
    _render_template(ctx, ctx.outputs.output)

    return [
        DefaultInfo(files = depset([ctx.outputs.output])),
    ]

kong_template_file = rule(
    implementation = _kong_template_file_impl,
    doc = "A rule that expands a template file",
    attrs = _kong_template_attrs,
)

def _kong_template_genrule_impl(ctx):
    f = ctx.actions.declare_file(ctx.attr.name + ".rendered.sh")
    _render_template(ctx, f)

    ctx.actions.run_shell(
        outputs = [ctx.outputs.output],
        inputs = ctx.files.srcs + ctx.files.tools + [f],
        command = "{} {}".format(f.path, ctx.outputs.output.path),
        progress_message = ctx.attr.progress_message,
    )

    return [
        # don't list f as files/real output
        DefaultInfo(files = depset([ctx.outputs.output])),
    ]

kong_template_genrule = rule(
    implementation = _kong_template_genrule_impl,
    doc = "A genrule that expands a template file and execute it",
    attrs = _kong_template_attrs | {
        "progress_message": attr.string(doc = "Message to display when running the command"),
    },
)

def _copyright_header(ctx):
    paths = ctx.execute(["find", ctx.path("."), "-type", "f"]).stdout.split("\n")

    copyright_content = ctx.read(ctx.path(Label("@kong//:distribution/COPYRIGHT-HEADER"))).replace("--", " ")
    copyright_content_js = "/*\n" + copyright_content + "*/\n\n"
    copyright_content_html = "<!--\n" + copyright_content + "-->\n\n"
    for path in paths:
        if path.endswith(".js") or path.endswith(".map") or path.endswith(".css"):
            content = ctx.read(path)
            if not content.startswith(copyright_content_js):
                # the default enabled |legacy_utf8| leads to a double-encoded utf-8
                # while writing utf-8 content read by |ctx.read|, let's disable it
                ctx.file(path, copyright_content_js + content, legacy_utf8 = False)

        elif path.endswith(".html"):
            content = ctx.read(path)
            if not content.startswith(copyright_content_html):
                # the default enabled |legacy_utf8| leads to a double-encoded utf-8
                # while writing utf-8 content read by |ctx.read|, let's disable it
                ctx.file(path, copyright_content_html + content, legacy_utf8 = False)

def _github_release_impl(ctx):
    ctx.file("WORKSPACE", "workspace(name = \"%s\")\n" % ctx.name)

    if ctx.attr.build_file:
        ctx.file("BUILD.bazel", ctx.read(ctx.attr.build_file))
    elif ctx.attr.build_file_content:
        ctx.file("BUILD.bazel", ctx.attr.build_file_content)

    os_name = ctx.os.name
    os_arch = ctx.os.arch

    if os_arch == "aarch64":
        os_arch = "arm64"
    elif os_arch == "x86_64":
        os_arch = "amd64"
    elif os_arch != "amd64":
        fail("Unsupported arch %s" % os_arch)

    if os_name == "mac os x":
        os_name = "macOS"
    elif os_name != "linux":
        fail("Unsupported OS %s" % os_name)

    gh_bin = "%s" % ctx.path(Label("@gh_%s_%s//:bin/gh" % (os_name, os_arch)))
    args = [gh_bin, "release", "download", ctx.attr.tag, "-R", ctx.attr.repo]
    downloaded_file = None
    if ctx.attr.pattern:
        if "/" in ctx.attr.pattern or ".." in ctx.attr.pattern:
            fail("/ and .. are not allowed in pattern")
        downloaded_file = ctx.attr.pattern.replace("*", "_")
        args += ["-p", ctx.attr.pattern]
    elif ctx.attr.archive:
        args.append("--archive=" + ctx.attr.archive)
        downloaded_file = "gh-release." + ctx.attr.archive.split(".")[-1]
    else:
        fail("at least one of pattern or archive must be set")

    args += ["-O", downloaded_file]

    ret = ctx.execute(args)

    if ret.return_code != 0:
        gh_token_set = "GITHUB_TOKEN is set, is it valid?"
        if not ctx.os.environ.get("GITHUB_TOKEN", ""):
            gh_token_set = "GITHUB_TOKEN is not set, is this a private repo?"
        fail("Failed to download release (%s): %s, exit: %d" % (gh_token_set, ret.stderr, ret.return_code))

    ctx.extract(downloaded_file, stripPrefix = ctx.attr.strip_prefix)

    # only used in EE: always skip here in CE
    if not ctx.attr.skip_add_copyright_header and False:
        _copyright_header(ctx)

github_release = repository_rule(
    implementation = _github_release_impl,
    doc = "Use `gh` CLI to download a github release and optionally add license headers",
    attrs = {
        "tag": attr.string(mandatory = True),
        "pattern": attr.string(mandatory = False),
        "archive": attr.string(mandatory = False, values = ["zip", "tar.gz"]),
        "strip_prefix": attr.string(default = "", doc = "Strip prefix from downloaded files"),
        "repo": attr.string(mandatory = True),
        "build_file": attr.label(allow_single_file = True),
        "build_file_content": attr.string(),
        "skip_add_copyright_header": attr.bool(default = False, doc = "Whether to inject COPYRIGHT-HEADER into downloaded files, only required for webuis"),
    },
)

def git_or_local_repository(name, branch, **kwargs):
    """A macro creates git_repository or local_repository based on the value of "branch".

    Args:
        name: the name of target
        branch: if starts with "." or "/", treat it as local_repository; otherwise git branch pr commit hash
        **kwargs: if build_file or build_file_content is set, the macros uses new_* variants.
    """

    new_repo = "build_file" in kwargs or "build_file_content" in kwargs
    if branch.startswith("/") or branch.startswith("."):
        print("Note @%s is initialized as a local repository from path %s" % (name, branch))

        func = new_repo and native.new_local_repository or native.local_repository
        func(
            name = name,
            path = branch,
            build_file = kwargs.get("build_file"),
            build_file_content = kwargs.get("build_file_content"),
        )
    else:
        func = new_repo and new_git_repository or git_repository

        # if "branch" is likely a commit hash, use it as commit
        if branch.isalnum() and len(branch) == 40:
            kwargs["commit"] = branch
            branch = None

        func(
            name = name,
            branch = branch,
            **kwargs
        )

def _kong_install_impl(ctx):
    outputs = []
    strip_path = ctx.attr.strip_path

    # TODO: `label.workspace_name` has been deprecated in the Bazel v7.1.0,
    # we should replace it with `label.repo_name` after upgrading
    # to the Bazel v7.
    # https://bazel.build/versions/7.1.0/rules/lib/builtins/Label
    label_path = ctx.attr.src.label.workspace_name + "/" + ctx.attr.src.label.name
    if not strip_path:
        strip_path = label_path
    prefix = ctx.attr.prefix
    if prefix:
        prefix = prefix + "/"

    for file in ctx.files.src:
        # skip top level directory
        if file.short_path.endswith(label_path) or file.short_path.endswith(strip_path):
            continue

        # strip ../ from the path
        path = file.short_path
        if file.short_path.startswith("../"):
            path = "/".join(file.short_path.split("/")[1:])

        # skip foreign_cc generated copy_* targets
        if path.startswith(ctx.attr.src.label.workspace_name + "/copy_" + ctx.attr.src.label.name):
            continue

        # skip explictly excluded directories
        should_skip = False
        for e in ctx.attr.exclude:
            if path.startswith(label_path + "/" + e):
                should_skip = True
                break
        if should_skip:
            continue

        # only replace the first one
        target_path = path.replace(strip_path + "/", "", 1)
        full_path = "%s/%s%s" % (KONG_VAR["BUILD_NAME"], prefix, target_path)

        # use a fake output, if we are writing a directory that may collide with others
        # nop_path = "%s-nop-farms/%s/%s/%s" % (KONG_VAR["BUILD_NAME"], strip_path, prefix, target_path)
        # output = ctx.actions.declare_file(nop_path)
        # ctx.actions.run_shell(
        #     outputs = [output],
        #     inputs = [file],
        #     command = "(mkdir -p {t} && chmod -R +rw {t} && cp -r {s} {t}) >{f}".format(
        #         t = full_path,
        #         s = file.path,
        #         f = output.path,
        #     ),
        # )
        if file.is_directory:
            output = ctx.actions.declare_directory(full_path)
            src = file.path + "/."  # avoid duplicating the directory name
        else:
            output = ctx.actions.declare_file(full_path)
            src = file.path
        ctx.actions.run_shell(
            outputs = [output],
            inputs = [file],
            command = "cp -r %s %s" % (src, output.path),
        )

        outputs.append(output)

        if full_path.find(".so.") >= 0 and ctx.attr.create_dynamic_library_symlink:
            el = full_path.split(".")
            si = el.index("so")
            sym_paths = []
            if len(el) > si + 2:  # has more than one part after .so like libX.so.2.3.4
                sym_paths.append(".".join(el[:si + 2]))  # libX.so.2
            sym_paths.append(".".join(el[:si + 1]))  # libX.so

            for sym_path in sym_paths:
                sym_output = ctx.actions.declare_symlink(sym_path)
                ctx.actions.symlink(output = sym_output, target_path = file.basename)
                outputs.append(sym_output)

    return [DefaultInfo(files = depset(outputs + ctx.files.deps))]

kong_install = rule(
    implementation = _kong_install_impl,
    doc = "Install files from the `src` label output to BUILD_DESTDIR",
    attrs = {
        "prefix": attr.string(
            mandatory = False,
            doc = "The relative prefix to add to target files, after KONG_VAR['BUILD_DESTDIR'], default to 'kong'",
            default = "kong",
        ),
        "strip_path": attr.string(
            mandatory = False,
            doc = "The leading path to strip from input, default to the ./<package/<target>",
            default = "",
        ),
        # "include": attr.string_list(
        #     mandatory = False,
        #     doc = "List of files to explictly install, take effect after exclude; full name, or exactly one '*' at beginning or end as wildcard are supported",
        #     default = [],
        # ),
        "exclude": attr.string_list(
            mandatory = False,
            doc = "List of directories to exclude from installation",
            default = [],
        ),
        "create_dynamic_library_symlink": attr.bool(
            mandatory = False,
            doc = "Create non versioned symlinks to the versioned so, e.g. libfoo.so -> libfoo.so.1.2.3",
            default = True,
        ),
        "deps": attr.label_list(allow_files = True, doc = "Labels to declare as dependency"),
        "src": attr.label(allow_files = True, doc = "Label to install files for"),
    },
)

def get_workspace_name(label):
    return label.replace("@", "").split("/")[0]

def _kong_cc_static_library_impl(ctx):
    linker_input = ctx.attr.src[CcInfo].linking_context.linker_inputs.to_list()[0]
    libs = []
    for lib in linker_input.libraries:
        libs.append(cc_common.create_library_to_link(
            actions = ctx.actions,
            # omit dynamic_library and pic_dynamic_library fields
            static_library = lib.static_library,
            pic_static_library = lib.pic_static_library,
            interface_library = lib.interface_library,
            alwayslink = lib.alwayslink,
        ))

    cc_info = CcInfo(
        compilation_context = ctx.attr.src[CcInfo].compilation_context,
        linking_context = cc_common.create_linking_context(
            linker_inputs = depset(direct = [
                cc_common.create_linker_input(
                    owner = linker_input.owner,
                    libraries = depset(libs),
                    user_link_flags = linker_input.user_link_flags,
                ),
            ]),
        ),
    )

    return [ctx.attr.src[OutputGroupInfo], cc_info]

kong_cc_static_library = rule(
    implementation = _kong_cc_static_library_impl,
    doc = "Filter a cc_library target to only output archive (.a) files",
    attrs = {
        "src": attr.label(allow_files = True, doc = "Label of a cc_library"),
    },
)
