using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using NuGet.Packaging.Core;

namespace Afas.BazelDotnet.Nuget
{
  public class LockFileGenerator
  {
    private readonly IDependencyResolver _dependencyResolver;

    public LockFileGenerator(string nugetConfig, string targetFramework, string targetRuntime)
      : this(new DependencyResolver(nugetConfig, targetFramework, targetRuntime))
    {
    }

    private LockFileGenerator(IDependencyResolver dependencyResolver)
    {
      _dependencyResolver = dependencyResolver;
    }

    public async Task Write(IEnumerable<(string package, string version)> packageReferences, string outputPath)
    {
      var packages = await _dependencyResolver.Resolve(packageReferences).ConfigureAwait(false);

      await using var file = File.Open(outputPath, FileMode.OpenOrCreate, FileAccess.ReadWrite);

      Dictionary<string, JToken> existing;
      {
        file.Seek(Encoding.UTF8.GetBytes("packages = ").Length, SeekOrigin.Begin);
        using var reader = new StreamReader(file, leaveOpen: true);
        var token = await JToken.ReadFromAsync(new JsonTextReader(reader));
        existing = token.ToDictionary(e => (string)e["id"], StringComparer.OrdinalIgnoreCase);
      }

      file.Seek(0, SeekOrigin.Begin);

      {
        await using var writer = new StreamWriter(file, leaveOpen: true);
        Write(existing, packages, writer);
      }

      file.SetLength(file.Position);
    }

    private void Write(Dictionary<string, JToken> existing, INugetRepositoryEntry[] nugetRepositoryEntries, TextWriter writer)
    {
      writer.WriteLine("packages = [");
      foreach(var entry in nugetRepositoryEntries.OrderBy(e => e.Id))
      {
        string version = entry.Version.ToString();
        string hash = entry.Hash;
        string source = entry.Source;

        if(existing.TryGetValue(entry.Id, out var prev))
        {
          var prevVersion = (string)prev["version"];
          if(string.Equals(entry.Version.ToString(), prevVersion))
          {
            version = prevVersion;
            source = (string)prev["sources"][0];
            hash = (string)prev["sha512"];
          }
        }

        writer.Write($@"{{""id"": ""{entry.Id}"", ""version"": ""{version}"", ""sha512"": ""{hash}"", ""sources"": [""{source}""], ""dependencies"": {{""net8.0"": [");
        foreach(var dependency in entry.DependencyGroups.SingleOrDefault()?.Packages ?? Array.Empty<PackageDependency>())
        {
          writer.Write($"\"{dependency.Id}\", ");
        }
        writer.WriteLine("]}},");
      }
      writer.WriteLine("]");
    }
  }
}
