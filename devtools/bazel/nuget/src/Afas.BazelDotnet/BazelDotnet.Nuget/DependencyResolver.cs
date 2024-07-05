using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using NuGet.Common;
using NuGet.Configuration;
using NuGet.Credentials;
using NuGet.Frameworks;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Protocol.Plugins;

namespace Afas.BazelDotnet.Nuget
{
  internal interface IDependencyResolver
  {
    Task<INugetRepositoryEntry[]> Resolve(IEnumerable<(string package, string version)> packageReferences);
  }

  internal class NpmRcCredentialProvider : ICredentialProvider
  {
    private Lazy<string> _npmRcContent = new(() =>
    {
      var path = Path.Combine(Environment.GetEnvironmentVariable("USERPROFILE"), ".npmrc");

      if(File.Exists(path))
      {
        return File.ReadAllText(path);
      }

      return null;
    });

    public Task<CredentialResponse> GetAsync(Uri uri, IWebProxy proxy, CredentialRequestType type, string message, bool isRetry, bool nonInteractive, CancellationToken cancellationToken)
    {
      // Read userprofile env
      if(_npmRcContent.Value == null)
      {
        return Task.FromResult(new CredentialResponse(CredentialStatus.ProviderNotApplicable));
      }

      var password = _npmRcContent.Value.Split('\n')
        .Select(line => line.Trim().Split('=', 2))
        .FirstOrDefault(kv => kv[0].Equals("//pkgs.dev.azure.com/afassoftware/_packaging/focus/npm/registry/:_password", StringComparison.OrdinalIgnoreCase))?[1];

      if(password == null)
      {
        return Task.FromResult(new CredentialResponse(CredentialStatus.ProviderNotApplicable));
      }

      if(string.Equals(uri.Host, "pkgs.dev.azure.com", StringComparison.OrdinalIgnoreCase))
      {
        return Task.FromResult(new CredentialResponse(new NetworkCredential(
          "VssSessionToken",
          Encoding.UTF8.GetString(Convert.FromBase64String(password)),
          uri.Host)));
      }

      return Task.FromResult(new CredentialResponse(CredentialStatus.ProviderNotApplicable));
    }

    public string Id { get; } = "npmrc";
  }

  internal class DependencyResolver : IDependencyResolver
  {
    private readonly string _nugetConfig;
    private readonly string _targetFramework;
    private readonly string _targetRuntime;

    public DependencyResolver(string nugetConfig, string targetFramework, string targetRuntime)
    {
      _nugetConfig = nugetConfig;
      _targetFramework = targetFramework;
      _targetRuntime = targetRuntime;
    }

    /// <summary>
    /// This method is copied from DefaultCredentialServiceUtility
    /// We add our own NpmRcCredentialProvider
    /// </summary>
    private static async Task<IEnumerable<ICredentialProvider>> GetCredentialProvidersAsync(
      ILogger logger)
    {
      var providers = (await new SecurePluginCredentialProviderBuilder(PluginManager.Instance, false, logger).BuildAllAsync()).ToList();

      providers.Add(new NpmRcCredentialProvider());

      if(providers.Any() && PreviewFeatureSettings.DefaultCredentialsAfterCredentialProviders)
      {
        providers.Add(new DefaultNetworkCredentialsCredentialProvider());
      }

      return providers;
    }

    public async Task<INugetRepositoryEntry[]> Resolve(IEnumerable<(string package, string version)> packageReferences)
    {
      // allow interactions for 2 factor authentication. CI scenario should never hit this.
      bool interactive = false;

      // prevent verbose logging when there could be interactive 2 factor output shown to the user.
      ILogger logger = new ConsoleLogger(interactive ? LogLevel.Minimal : LogLevel.Debug);
      var settings = Settings.LoadSpecificSettings(Path.GetDirectoryName(_nugetConfig), Path.GetFileName(_nugetConfig));
      // DefaultCredentialServiceUtility.SetupDefaultCredentialService(logger, nonInteractive: !interactive);
      HttpHandlerResourceV3.CredentialService =
        new(() => new CredentialService(
          new(() => GetCredentialProvidersAsync(logger)),
          nonInteractive: !interactive,
          handlesDefaultCredentials: PreviewFeatureSettings.DefaultCredentialsAfterCredentialProviders));

      // ~/.nuget/packages
      using var cache = new SourceCacheContext();

      var dependencyGraphResolver = new TransitiveDependencyResolver(settings, logger, cache);

      foreach(var (package, version) in packageReferences)
      {
        dependencyGraphResolver.AddPackageReference(package, version);
      }

      var dependencyGraph = await dependencyGraphResolver.ResolveGraph(_targetFramework, _targetRuntime).ConfigureAwait(false);
      var localPackages = await dependencyGraphResolver.DownloadPackages(dependencyGraph).ConfigureAwait(false);

      var entryBuilder = new NugetRepositoryEntryBuilder(logger, dependencyGraph.Conventions)
        .WithTarget(new FrameworkRuntimePair(NuGetFramework.Parse(_targetFramework), _targetRuntime));

      var entries = localPackages.Select(entryBuilder.ResolveGroups).ToArray();

      var (frameworkEntries, frameworkOverrides) = await new FrameworkDependencyResolver(dependencyGraphResolver)
        .ResolveFrameworkPackages(entries, _targetFramework)
        .ConfigureAwait(false);

      var overridenEntries = entries.Select(p =>
        frameworkOverrides.TryGetValue(p.LocalPackageSourceInfo.Package.Id, out var frameworkOverride)
          ? entryBuilder.BuildFrameworkOverride(p, frameworkOverride)
          : p);

      return frameworkEntries.Concat(overridenEntries).ToArray();

    }
  }
}