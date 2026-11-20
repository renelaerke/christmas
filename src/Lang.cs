using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;

namespace JuleHygge
{
    // The menu's texts in the user's language. The texts in the code are Danish, and the Danish text is the key:
    // a language is a file assets\sprog\xx.ini with lines "Danish text = text in that language" (see the README
    // there). A text a language lacks is shown in English, and one English lacks in Danish.
    //
    // The setting Language is empty for automatic (the default: Windows' display language when there is a file
    // for it, else English) or a language's code when the user has chosen in the menu "Sprog".
    // The same on macOS (Lang.swift) and Linux (linux/src/lang.rs), from the same files: build.ps1 puts every
    // file in assets\sprog into the exe as a resource named sprog.xx.ini.
    static class Lang
    {
        public sealed class Language
        {
            public string Code, Name;
            public Dictionary<string, string> Texts = new Dictionary<string, string>();
        }

        static Dictionary<string, Language> all;

        // Every language there is a file for, by code; Danish is always there.
        public static Dictionary<string, Language> All
        {
            get
            {
                if (all != null) return all;
                var found = new Dictionary<string, Language>();
                found["da"] = new Language { Code = "da", Name = "Dansk" };
                // the app's own files, then the user's (in a folder "sprog" beside settings.ini): a user's file wins
                try
                {
                    var asm = Assembly.GetExecutingAssembly();
                    foreach (string res in asm.GetManifestResourceNames())
                    {
                        if (!res.StartsWith("sprog.") || !res.EndsWith(".ini")) continue;
                        string code = res.Substring(6, res.Length - 10).ToLowerInvariant();
                        using (var stream = asm.GetManifestResourceStream(res))
                        using (var reader = new StreamReader(stream, Encoding.UTF8))
                            found[code] = Parse(code, reader.ReadToEnd());
                    }
                }
                catch { }
                try
                {
                    string dir = Path.Combine(Path.GetDirectoryName(Settings.FilePath), "sprog");
                    if (Directory.Exists(dir))
                        foreach (string file in Directory.GetFiles(dir, "*.ini"))
                        {
                            string code = Path.GetFileNameWithoutExtension(file).ToLowerInvariant();
                            found[code] = Parse(code, File.ReadAllText(file, Encoding.UTF8));
                        }
                }
                catch { }
                all = found;
                return all;
            }
        }

        // "Danish text = translation" per line; "#" starts a comment; "@name" is the language's own name.
        public static Language Parse(string code, string text)
        {
            var l = new Language { Code = code, Name = code };
            foreach (string raw in text.Split('\n'))
            {
                string line = raw.Trim();
                if (line.StartsWith("#")) continue;
                int i = line.IndexOf(" = ", StringComparison.Ordinal);
                if (i <= 0) continue;
                string key = line.Substring(0, i).Trim(), value = line.Substring(i + 3).Trim();
                if (key == "@name") l.Name = value;
                else if (value.Length > 0) l.Texts[key] = value;
            }
            return l;
        }

        // The languages for the menu, Danish and English first, then by name.
        public static List<Language> Listed
        {
            get
            {
                var list = new List<Language>(All.Values);
                list.Sort((a, b) =>
                {
                    int ra = a.Code == "da" ? 0 : a.Code == "en" ? 1 : 2, rb = b.Code == "da" ? 0 : b.Code == "en" ? 1 : 2;
                    return ra != rb ? ra.CompareTo(rb) : string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase);
                });
                return list;
            }
        }

        static string automatic;

        // Windows' display language when there is a file for it; English otherwise.
        // JULE_LOCALE=de_DE pretends to be that locale (for tests).
        public static string Automatic
        {
            get
            {
                if (automatic != null) return automatic;
                string wanted = null;
                string fake = Environment.GetEnvironmentVariable("JULE_LOCALE");
                if (!string.IsNullOrEmpty(fake)) { string region; Folk.Split(fake, out wanted, out region); }
                else { try { wanted = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName; } catch { } }
                wanted = (wanted ?? "").ToLowerInvariant();
                automatic = All.ContainsKey(wanted) ? wanted : "en";
                return automatic;
            }
        }

        // The setting Language (set when the settings are read and when the user chooses in the menu).
        public static string Setting = "";
        // The language in use.
        public static string Code { get { return !string.IsNullOrEmpty(Setting) && All.ContainsKey(Setting) ? Setting : Automatic; } }

        public static string NameOf(string code)
        {
            Language l;
            return All.TryGetValue(code, out l) ? l.Name : code;
        }

        // A menu text in the user's language. {0}, {1} ... are replaced by the arguments.
        public static string T(string da, params object[] args)
        {
            string s = da, c = Code;
            if (c != "da")
            {
                Language l; string t;
                if (All.TryGetValue(c, out l) && l.Texts.TryGetValue(da, out t)) s = t;
                else if (All.TryGetValue("en", out l) && l.Texts.TryGetValue(da, out t)) s = t;
            }
            for (int i = 0; i < args.Length; i++) s = s.Replace("{" + i + "}", Convert.ToString(args[i], CultureInfo.InvariantCulture));
            return s;
        }

        // Test aid (--sprog-test[=FILE]): the languages found, the automatic choice, and what each lacks against
        // English. Written to FILE (the exe has no console on Windows), or to the console without one.
        public static void Test(string file)
        {
            var lines = new List<string>();
            lines.Add("Automatisk på denne maskine: " + Automatic + " (" + NameOf(Automatic) + ")");
            Language en;
            var english = All.TryGetValue("en", out en) ? en.Texts : new Dictionary<string, string>();
            foreach (var l in Listed)
            {
                var missing = new List<string>();
                if (l.Code != "da") foreach (string k in english.Keys) if (!l.Texts.ContainsKey(k)) missing.Add(k);
                lines.Add("  " + l.Code + "  " + l.Name + ": " + l.Texts.Count + " tekster" + (missing.Count > 0 ? ", mangler " + missing.Count : ""));
                foreach (string m in missing) lines.Add("      mangler: " + m);
            }
            if (string.IsNullOrEmpty(file)) foreach (string line in lines) Console.WriteLine(line);
            else File.WriteAllLines(file, lines.ToArray(), Encoding.UTF8);
        }
    }
}
