using System;
using System.Linq;
using System.Reflection;

namespace simpleresgen
{
    class Program
    {
        static void Main(string[] args)
        {
          args = args.SelectMany(a => a.StartsWith("@") ? System.IO.File.ReadLines(a.Substring(1)) : new[] { a }).ToArray();

            var infiles = args[0..^1];
            var outfile = args[args.Length - 1];
            try
            {
                var translator = new Translator();
                translator.Translate(infiles, outfile);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Exception: {ex.ToString()}\n{ex.StackTrace}");
                Environment.Exit(-1);
            }
        }
    }
}
