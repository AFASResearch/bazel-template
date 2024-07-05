using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Xml.Linq;
using Afas.BazelDotnet.Nuget;
using McMaster.Extensions.CommandLineUtils;

namespace Afas.BazelDotnet
{
  public class Program
  {
    public static void Main(string[] args)
    {
      var app = new CommandLineApplication
      {
        Name = "BazelDotnet",
        Description = "Bazel Nuget Lock File generator for .NET Core projects",
      };

      app.HelpOption("-?|-h|--help");

      // set the WorkingDir!
      // repository C:/Anta/platform/nuget.config -p C:/Anta/platform/Packages.Props
      app.Command("repository", repoCmd =>
      {
        var nugetConfig = repoCmd.Argument("nuget.config", "The path to the nuget.config file");
        var packagesProps = repoCmd.Argument("Directory.Packages.props", "The path to the Packages.Props file");
        var output = repoCmd.Argument("output", "the path to the output .bzl file");
        var tfmOption = repoCmd.Option("-t|--tfm", "The target framework to restore", CommandOptionType.SingleOrNoValue);

        repoCmd.OnExecuteAsync(async _ =>
        {
          var packagePropsFilePaths = packagesProps.Values.Select(v => Path.Combine(Directory.GetCurrentDirectory(), v)).ToArray();
          var nugetConfigFilePath = Path.Combine(Directory.GetCurrentDirectory(), nugetConfig.Value);
          var tfm = tfmOption.HasValue() ? tfmOption.Value() : "net8.0";
          await WriteRepository(tfm, packagePropsFilePaths, nugetConfigFilePath, Path.Combine(Directory.GetCurrentDirectory(), output.Value!)).ConfigureAwait(false);
          return 0;
        });
      });


      if(!args.Any())
      {
        app.ShowHelp();
        throw new Exception("No arguments provided");
      }

      app.Execute(args);
    }

    private static (string, string)[] ResolvePackages(string packageProps)
    {
      if(File.Exists(packageProps))
      {
        var packagesProps = XElement.Load(packageProps);

        return packagesProps
          .Element("ItemGroup")
          .Elements("PackageVersion")
          .Select(el => (el.Attribute("Include")?.Value, el.Attribute("Version")?.Value))
          .Where(Included)
          .ToArray();
      }

      return Directory.EnumerateFiles(packageProps, "*.csproj", SearchOption.AllDirectories)
        .Select(XDocument.Load)
        .SelectMany(f => f.Descendants("PackageReference"))
        .Select(p => (p.Attribute("Include")?.Value, p.Attribute("Version")?.Value))
        .Where(t => t.Item1 != null && t.Item2 != null)
        .Distinct()
        .ToArray();

      bool Included((string update, string version) arg) =>
        !string.IsNullOrEmpty(arg.update) &&
        !string.IsNullOrEmpty(arg.version) &&
        !arg.version.EndsWith("-local-dev", StringComparison.OrdinalIgnoreCase);
    }

    private static async Task WriteRepository(string tfm, IEnumerable<string> packagePropsFiles, string nugetConfig, string outputPath)
    {
      // Note: no conlict resolution. Maybe we can add them in the dep graph. For now multiple Packages.Props is not really a use case anymore
      (string, string)[] deps = packagePropsFiles
        .SelectMany(ResolvePackages)
        .Distinct()
        .ToArray();

      await new LockFileGenerator(nugetConfig, tfm, "win-x64")
        .Write(deps, outputPath)
        .ConfigureAwait(false);
    }
  }
}
