// See https://aka.ms/new-console-template for more information

using Microsoft.Build.Tasks.Windows;
using System;
using System.CodeDom.Compiler;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using Microsoft.CSharp;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;

IEnumerable<string> Expand(string arg)
{
  if(arg.StartsWith("@"))
  {
    return File.ReadLines(arg.Substring(1));
  }

  return [arg];
}

var xamls = new List<string>();
var sources = new List<string>();
var references = new List<string>();
string outputFolder = "";
string? appXaml = null;
foreach(var arg in args.SelectMany(Expand))
{
  if (arg.StartsWith("/x:"))
  {
    var xaml = arg.Substring(3).Trim('"');
    if(Path.GetFileName(xaml) == "App.xaml")
    {
      appXaml = xaml;
    }
    else
    {
      xamls.Add(xaml);
    }
  }
  else if (arg.StartsWith("/s:"))
  {
    sources.Add(arg.Substring(3).Trim('"'));
  }
  else if (arg.StartsWith("/r:"))
  {
    references.Add(arg.Substring(3).Trim('"'));
  }
  else
  {
    outputFolder = arg.Trim('"');
  }
}

var root = Directory.GetCurrentDirectory();
var projectPath = outputFolder[(outputFolder.IndexOf("/bin/") + "/bin/".Length) .. (outputFolder ?? "").IndexOf("/g")];

var pageMarkup = xamls.Select(p => new TaskItem(Path.GetRelativePath(projectPath, p))).ToArray();
var applicationMarkup = appXaml == null ? null : new[] { new TaskItem(Path.GetRelativePath(projectPath, appXaml)) };
var refItems = references.Select(r => new TaskItem(Path.GetRelativePath(projectPath, r))).ToArray();
var sourceItems = sources.Select(r => new TaskItem(Path.GetRelativePath(projectPath, r))).ToArray();

Directory.SetCurrentDirectory(Path.Combine(root, projectPath));

var pass1 = new MarkupCompilePass1()
{
  OutputType = appXaml != null ? "exe" : "library",
  AssemblyName = Path.GetFileName(Path.GetDirectoryName(outputFolder)),
  PageMarkup = pageMarkup,
  ApplicationMarkup = applicationMarkup,
  // AlwaysCompileMarkupFilesInSeparateDomain = true,
  DefineConstants = "TRACE;DEBUG;NET;NET8_0;NETCOREAPP",
  Language = "C#",
  OutputPath = Path.Combine(root, outputFolder!),
  References = refItems,
  XamlDebuggingInformation = true,
  RootNamespace = "Afas",
  // LocalizationDirectivesToLocFile = "None",
  SourceCodeFiles = sourceItems,
  HostInBrowser = "false",
  // KnownReferencePaths = [@"C:\Program Files\dotnet\sdk\8.0.303"],
  LanguageSourceExtension = ".cs",
};

Engine engine = new Engine();

pass1.BuildEngine = engine;

if(!pass1.Execute())
{
  throw new Exception("Returned false!");
}

string tempDll = Path.Combine(root, outputFolder!, Path.GetFileName(Path.GetDirectoryName(outputFolder)) + ".dll");

var compilation = CSharpCompilation.Create(
  Path.GetFileName(Path.GetDirectoryName(outputFolder)),
  Directory.GetFiles(Path.Combine(root, outputFolder!), "*.g.cs", SearchOption.AllDirectories)
    .Concat(sources.Select(r => (Path.GetRelativePath(projectPath, r))))
    .Select(f => CSharpSyntaxTree.ParseText(File.ReadAllText(f), path: f))
    .ToArray(),
  references.Select(r => MetadataReference.CreateFromFile(Path.GetRelativePath(projectPath, r))).ToArray(),
  options: new CSharpCompilationOptions(outputKind: OutputKind.DynamicallyLinkedLibrary));

var diagnostics = compilation.GetDiagnostics();
bool IsError(Diagnostic d) => d.Severity == DiagnosticSeverity.Error;
if(diagnostics.Any(IsError))
{
  throw new Exception(string.Join("\n", diagnostics.Where(IsError).Select(d => d.ToString())));
}

var result = compilation.Emit(outputPath: tempDll);
if(result.Diagnostics.Any(IsError))
{
  throw new Exception(string.Join("\n", result.Diagnostics.Where(IsError).Select(d => d.ToString())));
}

// var result = CodeDomProvider.CreateProvider("c#")
//   .CompileAssemblyFromSource(
//     new CompilerParameters(
//       references.Select(r => Path.GetRelativePath(projectPath, r)).ToArray(),
//       outputName: tempDll),
//     Directory.GetFiles(Path.Combine(root, outputFolder!), "*.g.cs", SearchOption.AllDirectories)
//       .Select(File.ReadAllText)
//       .ToArray());

var pass2 = new MarkupCompilePass2()
{
  OutputType = appXaml != null ? "exe" : "library",
  AssemblyName = Path.GetFileName(Path.GetDirectoryName(outputFolder)),
  Language = "C#",
  RootNamespace = "Afas",
  // AlwaysCompileMarkupFilesInSeparateDomain = true,
  XamlDebuggingInformation = true,
  OutputPath = Path.Combine(root, outputFolder!),
  References = refItems.Append(new TaskItem(tempDll)).ToArray(),
};

pass2.BuildEngine = engine;

if(!pass2.Execute())
{
  throw new Exception("Returned false!");
}

class MyEngineServices : EngineServices
{
  public override bool LogsMessagesOfImportance(MessageImportance importance) => importance <= MessageImportance.Normal;
}

class Engine : IBuildEngine10
{
  public void LogErrorEvent(BuildErrorEventArgs e) => Console.WriteLine(e.Message);

  public void LogWarningEvent(BuildWarningEventArgs e) => Console.WriteLine(e.Message);

  public void LogMessageEvent(BuildMessageEventArgs e) => Console.WriteLine(e.Message);

  public void LogCustomEvent(CustomBuildEventArgs e) => Console.WriteLine(e.Message);

  public bool BuildProjectFile(string projectFileName, string[] targetNames, IDictionary globalProperties,
    IDictionary targetOutputs) =>
    throw new NotImplementedException();

  public bool ContinueOnError => true;
  public int LineNumberOfTaskNode { get; }
  public int ColumnNumberOfTaskNode { get; }
  public string ProjectFileOfTaskNode { get; }

  public bool BuildProjectFile(string projectFileName, string[] targetNames, IDictionary globalProperties,
    IDictionary targetOutputs, string toolsVersion) =>
    throw new NotImplementedException();

  public bool BuildProjectFilesInParallel(string[] projectFileNames, string[] targetNames, IDictionary[] globalProperties,
    IDictionary[] targetOutputsPerProject, string[] toolsVersion, bool useResultsCache, bool unloadProjectsOnCompletion) =>
    throw new NotImplementedException();

  public bool IsRunningMultipleNodes { get; }

  public BuildEngineResult BuildProjectFilesInParallel(string[] projectFileNames, string[] targetNames,
    IDictionary[] globalProperties, IList<string>[] removeGlobalProperties, string[] toolsVersion, bool returnTargetOutputs) =>
    throw new NotImplementedException();

  public void Yield() => throw new NotImplementedException();

  public void Reacquire() => throw new NotImplementedException();

  public void RegisterTaskObject(object key, object obj, RegisteredTaskObjectLifetime lifetime, bool allowEarlyCollection) => throw new NotImplementedException();

  public object GetRegisteredTaskObject(object key, RegisteredTaskObjectLifetime lifetime) => throw new NotImplementedException();

  public object UnregisterTaskObject(object key, RegisteredTaskObjectLifetime lifetime) => throw new NotImplementedException();

  public void LogTelemetry(string eventName, IDictionary<string, string> properties) => throw new NotImplementedException();

  public IReadOnlyDictionary<string, string> GetGlobalProperties() => throw new NotImplementedException();

  public bool AllowFailureWithoutError { get; set; }
  public bool ShouldTreatWarningAsError(string warningCode) => true;

  public int RequestCores(int requestedCores) => throw new NotImplementedException();

  public void ReleaseCores(int coresToRelease) => throw new NotImplementedException();

  public EngineServices EngineServices { get; } = new MyEngineServices();
}
