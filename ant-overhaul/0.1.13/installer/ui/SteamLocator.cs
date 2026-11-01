using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace AntOverhaulInstaller
{
    internal static class SteamLocator
    {
        internal static string Find()
        {
            List<string> steamRoots = new List<string>();
            try { using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")) if (key != null) Add(steamRoots, key.GetValue("SteamPath") as string); } catch { }
            foreach (RegistryView view in new[] { RegistryView.Registry32, RegistryView.Registry64 })
            {
                try { using (RegistryKey hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view)) using (RegistryKey key = hive.OpenSubKey(@"Software\Valve\Steam")) if (key != null) Add(steamRoots, key.GetValue("InstallPath") as string); } catch { }
            }
            Add(steamRoots, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Steam"));
            List<string> libraries = new List<string>(steamRoots);
            foreach (string steam in steamRoots)
            {
                try
                {
                    string file = Path.Combine(steam, @"steamapps\libraryfolders.vdf");
                    if (!File.Exists(file)) continue;
                    foreach (Match match in Regex.Matches(File.ReadAllText(file), "\"path\"\\s+\"((?:\\\\.|[^\"\\\\])*)\"", RegexOptions.IgnoreCase)) Add(libraries, Unescape(match.Groups[1].Value));
                }
                catch { }
            }
            foreach (string library in libraries)
            {
                try
                {
                    string folder = "Empires of the Undergrowth";
                    string manifest = Path.Combine(library, @"steamapps\appmanifest_463530.acf");
                    if (File.Exists(manifest))
                    {
                        Match match = Regex.Match(File.ReadAllText(manifest), "\"installdir\"\\s+\"((?:\\\\.|[^\"\\\\])*)\"", RegexOptions.IgnoreCase);
                        if (match.Success) folder = Unescape(match.Groups[1].Value);
                    }
                    string common = Path.GetFullPath(Path.Combine(library, @"steamapps\common"));
                    string game = Path.GetFullPath(Path.Combine(common, folder));
                    if (game.StartsWith(common + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) && File.Exists(Path.Combine(game, "EotU.exe"))) return game;
                }
                catch { }
            }
            return null;
        }
        private static string Unescape(string value) { return value.Replace("\\\\", "\\").Replace("\\\"", "\""); }
        private static void Add(List<string> values, string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return;
            try { string path = Path.GetFullPath(value.Replace('/', Path.DirectorySeparatorChar)); if (!values.Exists(delegate(string x) { return string.Equals(x, path, StringComparison.OrdinalIgnoreCase); })) values.Add(path); } catch { }
        }
    }
}
