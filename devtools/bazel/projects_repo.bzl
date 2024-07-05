load("@bazel_tools//tools/build_defs/repo:utils.bzl", "patch")

def _root(ctx):
  return ctx.path(ctx.attr.workspace).dirname

def _args(ctx):
  args = [
    "-p=.",
    # @nuget prefix
    "-w={}".format(ctx.attr.nuget_repo),
  ]

  # imports
  args += ["-i @{}={}".format(label.workspace_name, ctx.path(label)) for label in ctx.attr.imports]

  args += ["--search={}".format(s) for s in ctx.attr.search]

  args += ["-v {}={}".format(pattern, ",".join(visibilities)) for pattern, visibilities in ctx.attr.visibilities.items()]

  return args

def _cmds(ctx, args):
  return [
      str(ctx.path(ctx.attr.dotnet_binary)),
      str(ctx.path(ctx.attr._bazel_dotnet)),
      "projects",
  ] + args

def _run(ctx, args):
  r = ctx.execute(_cmds(ctx, args), environment = {
    # Some IDE's (Rider) set this to 0 which results in issues when BazelDotnet is compiler with a different SDK than loaded
    "DOTNET_MULTILEVEL_LOOKUP": "1"
  })

  if r.return_code != 0:
    print(r.stdout)
    print(r.return_code)
    fail(r.stderr)

# run git clean on new_.. to ensure clean up is done right
def _projects_ci(ctx, path, git_clean = False):
  ctx.file("projects_ci.cmd", (r"""@echo off
cd {root}
git clean -xfd {globs} >nul
{cmds}
""" if git_clean else r"""@echo off
cd {root}
{cmds}
""").format(
    root = path,
    globs = " ".join(["{}/**/BUILD".format(s) for s in ctx.attr.search]) if len(ctx.attr.search) else "**/BUILD",
    cmds = " ".join(_cmds(ctx, _args(ctx)))
  ))

# run from platform. also fix backend
def _fix(ctx):
  ctx.file("fix.cmd", r"""@echo off
cd {root}

bazel sync --only projects --only backend
bazel build ... --output_groups=targets
""".format(
    root = _root(ctx),
    globs = " ".join(["{}/**/BUILD".format(s) for s in ctx.attr.search]),
    cmds = " ".join(_cmds(ctx, _args(ctx)))
  ))

# link all search directories
def _link_search(ctx, root):
    found_all = True
    for s in ctx.attr.search:
      p = ctx.path("{}/{}".format(root, s))
      if p.exists:
        ctx.symlink(p, s)
      else:
        found_all = False
    return found_all

def _projects_repo_impl(ctx):
  # No need to run projects in our repository rule because CI calls the projects_ci.cmd manually
  if ctx.os.environ.get("PIPELINE_WORKSPACE") == None:
    found_all = _link_search(ctx, _root(ctx))

    _run(ctx, _args(ctx))

    # currently we can onely safely execute patches when all search patterns were found
    # /backend may not exist but we are patching it
    if found_all:
      patch(ctx)

  _projects_ci(ctx, _root(ctx))
  _fix(ctx)
  ctx.file("fix.bzl", "def fix():\n  return 0")
  ctx.file("BUILD", r"""exports_files(["fix.bzl", "fix.cmd", "projects_ci.cmd"])""")

def _new_projects_repo_impl(ctx):
  args = _args(ctx)

  dir = _root(ctx)
  relp = ctx.path("{}/{}".format(dir, ctx.attr.path))
  # link new_repo_path
  if relp.exists:
    _link_search(ctx, relp)

    _run(ctx, args)

    patch(ctx)

    _projects_ci(ctx, relp, git_clean = True)
  else:
    # add stubs
    ctx.file(".bazel-projects", "")
    ctx.file("projects_ci.cmd", "@echo off\n")

  # Add the same context data to the repo
  if ctx.attr.build_file:
    ctx.file("BUILD", ctx.read(ctx.attr.build_file))

projects_repo = repository_rule(
    _projects_repo_impl,
    local=True,
    attrs = {
        "workspace": attr.label(default = "@//:.gitattributes"),
        "search": attr.string_list(),
        "nuget_repo": attr.string(default = "nuget"),
        "imports": attr.label_list(default = []),
        "_bazel_dotnet": attr.label(default = "@bazel_dotnet//:Afas.BazelDotnet.dll", allow_single_file = True),
        "dotnet_binary": attr.label(default = "@core_sdk//:dotnet.exe", allow_single_file = True),
        "visibilities": attr.string_list_dict(),

        "patches": attr.label_list(
            default = [],
            doc =
                "A list of files that are to be applied as patches after " +
                "extracting the archive. By default, it uses the Bazel-native patch implementation " +
                "which doesn't support fuzz match and binary patch, but Bazel will fall back to use " +
                "patch command line tool if `patch_tool` attribute is specified or there are " +
                "arguments other than `-p` in `patch_args` attribute.",
        ),
        "remote_patches": attr.string_dict(
            default = {},
            doc =
                "A map of patch file URL to its integrity value, they are applied after extracting " +
                "the archive and before applying patch files from the `patches` attribute. " +
                "It uses the Bazel-native patch implementation, you can specify the patch strip " +
                "number with `remote_patch_strip`",
        ),
        "remote_patch_strip": attr.int(
            default = 0,
            doc =
                "The number of leading slashes to be stripped from the file name in the remote patches.",
        ),
        "patch_tool": attr.string(
            default = "",
            doc = "The patch(1) utility to use. If this is specified, Bazel will use the specified " +
                  "patch tool instead of the Bazel-native patch implementation.",
        ),
        "patch_args": attr.string_list(
            default = ["-p0"],
            doc =
                "The arguments given to the patch tool. Defaults to -p0, " +
                "however -p1 will usually be needed for patches generated by " +
                "git. If multiple -p arguments are specified, the last one will take effect." +
                "If arguments other than -p are specified, Bazel will fall back to use patch " +
                "command line tool instead of the Bazel-native patch implementation. When falling " +
                "back to patch command line tool and patch_tool attribute is not specified, " +
                "`patch` will be used. This only affects patch files in the `patches` attribute.",
        ),
        "patch_cmds": attr.string_list(
            default = [],
            doc = "Sequence of Bash commands to be applied on Linux/Macos after patches are applied.",
        ),
        "patch_cmds_win": attr.string_list(
            default = [],
            doc = "Sequence of Powershell commands to be applied on Windows after patches are " +
                  "applied. If this attribute is not set, patch_cmds will be executed on Windows, " +
                  "which requires Bash binary to exist.",
        ),
    },
)

new_projects_repo = repository_rule(
    _new_projects_repo_impl,
    local=True,
    attrs = {
        "workspace": attr.label(default = "@//:.gitattributes"),
        "search": attr.string_list(default = []),
        "path": attr.string(),
        "build_file": attr.label(allow_single_file = True, default = None),
        "nuget_repo": attr.string(),
        "imports": attr.label_list(default = []),
        "_bazel_dotnet": attr.label(default = "@bazel_dotnet//:Afas.BazelDotnet.dll", allow_single_file = True),
        "dotnet_binary": attr.label(default = "@core_sdk//:dotnet.exe", allow_single_file = True),
        "visibilities": attr.string_list_dict(),

        "patches": attr.label_list(
            default = [],
            doc =
                "A list of files that are to be applied as patches after " +
                "extracting the archive. By default, it uses the Bazel-native patch implementation " +
                "which doesn't support fuzz match and binary patch, but Bazel will fall back to use " +
                "patch command line tool if `patch_tool` attribute is specified or there are " +
                "arguments other than `-p` in `patch_args` attribute.",
        ),
        "remote_patches": attr.string_dict(
            default = {},
            doc =
                "A map of patch file URL to its integrity value, they are applied after extracting " +
                "the archive and before applying patch files from the `patches` attribute. " +
                "It uses the Bazel-native patch implementation, you can specify the patch strip " +
                "number with `remote_patch_strip`",
        ),
        "remote_patch_strip": attr.int(
            default = 0,
            doc =
                "The number of leading slashes to be stripped from the file name in the remote patches.",
        ),
        "patch_tool": attr.string(
            default = "",
            doc = "The patch(1) utility to use. If this is specified, Bazel will use the specified " +
                  "patch tool instead of the Bazel-native patch implementation.",
        ),
        "patch_args": attr.string_list(
            default = ["-p0"],
            doc =
                "The arguments given to the patch tool. Defaults to -p0, " +
                "however -p1 will usually be needed for patches generated by " +
                "git. If multiple -p arguments are specified, the last one will take effect." +
                "If arguments other than -p are specified, Bazel will fall back to use patch " +
                "command line tool instead of the Bazel-native patch implementation. When falling " +
                "back to patch command line tool and patch_tool attribute is not specified, " +
                "`patch` will be used. This only affects patch files in the `patches` attribute.",
        ),
        "patch_cmds": attr.string_list(
            default = [],
            doc = "Sequence of Bash commands to be applied on Linux/Macos after patches are applied.",
        ),
        "patch_cmds_win": attr.string_list(
            default = [],
            doc = "Sequence of Powershell commands to be applied on Windows after patches are " +
                  "applied. If this attribute is not set, patch_cmds will be executed on Windows, " +
                  "which requires Bash binary to exist.",
        ),
    },
)
