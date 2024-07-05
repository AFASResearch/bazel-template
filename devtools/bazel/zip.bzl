"""
Defines zip

By default a folder is created: {name}/{library}.exe
Currently no deps.json is generated. If the need arises look at write_depsjson

specify --output_groups zip or :{zip_output} to create a zip
The zip is never cached because it's highly volatile
"""

def _create_zip(ctx, zip_file, files):
    if not zip_file:
        zip_file = ctx.actions.declare_file(ctx.attr.name)

    args = ctx.actions.args()
    args.use_param_file("@%s")
    # the ./ prefix strips folder structure
    args.add_all(files, format_each = "./%s/*" if ctx.attr.folders else "./%s")
    ctx.actions.run(
        executable = "C:\\Program Files\\7-Zip\\7z.exe",
        arguments = ["a", "-tzip", zip_file.path, "-mtm-", args],
        inputs = files,
        outputs = [zip_file],
        execution_requirements = {
            # The zip is never cached because it's highly volatile
            "no-cache": "1",
        }
    )
    return zip_file

def _unsupported(f):
    # This is a workaround
    # 1) conflict resolution in BazelDotnet should resolve this
    # But because it works on package names it failes to recognize
    # BouncyCastle.Crypto.dll is in bouncycastle.netcore and portable.bouncycastle
    return f.path.find("bouncycastle.netcore") != -1

def _zip_impl(ctx):
    zip_files = []
    result_link = None

    # Collect only unique filenames, we assume that equal filenames means equal files
    collected = dict()
    # Collect all files top zip
        # we ignore targetFolder right now,
        # but we in the future we should use it as a relative path within the zip file
    for f in ctx.files.sources:
        if _unsupported(f) or collected.get(f.basename) != None:
            continue

        # TODO podium becomes part of the generator data [] now. For some reason this was excluded before
        if f.path.find("podium") != -1:
            continue

        collected[f.basename] = True
        zip_files.append(f)
        
    zip_file = _create_zip(ctx, ctx.outputs.zip_output, zip_files)
    
    return [
        DefaultInfo(
            files = depset([zip_file]),
        )
    ]

zip = rule(
    _zip_impl,
    attrs = {
        "sources": attr.label_keyed_string_dict(allow_files = True),
        "folders": attr.bool(default = False),
        "zip_output": attr.output(),
    }
)