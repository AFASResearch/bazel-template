using System;
using System.Runtime.Loader;

internal class StartupHook
{
    public static void Initialize()
    {
        if (BazelManifest.TryRead(out var manifest))
        {
            AssemblyLoadContext.Default.Resolving += manifest.Resolve;
            AssemblyLoadContext.Default.ResolvingUnmanagedDll += manifest.ResolveUnmanagedDll;
        }
    }
}
