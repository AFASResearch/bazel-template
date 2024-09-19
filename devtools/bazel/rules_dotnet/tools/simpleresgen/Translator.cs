using System.Collections;
using System.IO;
using Microsoft.Build.Tasks.ResourceHandling;

namespace simpleresgen
{
    public class Translator
    {
        public void Translate(string[] infiles, string outfile)
        {
            var writer = new System.Resources.ResourceWriter(outfile);

            foreach(var infile in infiles)
            {
                if(infile.EndsWith(".resx"))
                {
                    foreach(var resource in MSBuildResXReader.GetResourcesFromFile(infile, pathsRelativeToBasePath: true))
                    {
                        resource.AddTo(writer);
                    }
                }
                else
                {
                  var split = infile.Split(',');

                  writer.AddResource(split[1].ToLower(), new MemoryStream(File.ReadAllBytes(split[0]))
                  {
                    Position = 0
                  });
                }
            }

            writer.Generate();
            writer.Close();
        }
    }
}
