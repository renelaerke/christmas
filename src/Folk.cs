using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace JuleHygge
{
    // Who walks on the taskbar in the Christmas theme: the Nordic nisse (red hat, grey clothes, white beard), or
    // the Christmas elf most of the rest of the world expects (green and red, pointed ears and cap, striped
    // stockings, no beard). They are the same walkers in everything but looks (Layer.DrawNisse and DrawElf).
    // As the macOS version (Folk.swift), with the same rule and the same setting.
    //
    // The setting Folk is 0 = automatic (the default: decided by the user's language and region, below), or one
    // of the two values here when the user has chosen in the menu because the automatic choice was wrong for them.
    static class Folk
    {
        // The Nordic nisse; the Christmas elf; and three nisse-like figures with their own looks: the German
        // Wichtel (a tall felt cap pulled down over the eyes, a long beard, hardly any legs), the Dutch kabouter
        // (a stiff cone hat, a short beard, clogs) and the Estonian päkapikk (all in red with white trim, no beard).
        public const int Nisser = 1, Alfer = 2, Wichtel = 3, Kabouter = 4, Paekapikk = 5;
        public static readonly string[] Names = { "Nisser", "Alfer", "Wichtel (tyske nisser)", "Kabouters (hollandske nisser)", "Päkapikud (estiske nisser)" };
        static readonly string[] ShortNames = { "nisser", "alfer", "wichtel", "kabouter", "paekapikk" };
        public static string Name(int folk) { return Names[folk - 1]; }

        // Who gets which figure: by language first, then by region; everyone else gets elves. These two tables
        // are the whole rule (the same as in Folk.swift and linux/src/folk.rs).
        // The Nordic ones: the nisse and its close relatives (tomte, tonttu, jólasveinar).
        static readonly Dictionary<string, int> ByLanguage = new Dictionary<string, int> {
            { "da", Nisser }, { "nb", Nisser }, { "nn", Nisser }, { "no", Nisser }, { "sv", Nisser }, { "fi", Nisser },
            { "fo", Nisser }, { "is", Nisser }, { "kl", Nisser }, { "se", Nisser },
            { "de", Wichtel }, { "nl", Kabouter }, { "et", Paekapikk } };
        static readonly Dictionary<string, int> ByRegion = new Dictionary<string, int> {
            { "DK", Nisser }, { "NO", Nisser }, { "SE", Nisser }, { "FI", Nisser }, { "FO", Nisser }, { "GL", Nisser },
            { "IS", Nisser }, { "AX", Nisser }, { "SJ", Nisser },
            { "DE", Wichtel }, { "AT", Wichtel }, { "CH", Wichtel }, { "LI", Wichtel }, { "NL", Kabouter }, { "EE", Paekapikk } };

        // The language decides when it has a figure of its own: a Dane abroad keeps the nisser. Otherwise the
        // region does: someone living in Denmark with Windows set to English gets nisser too.
        public static int Automatic(string language, string region)
        {
            int f;
            if (language != null && ByLanguage.TryGetValue(language.ToLowerInvariant(), out f)) return f;
            if (region != null && ByRegion.TryGetValue(region.ToUpperInvariant(), out f)) return f;
            return Alfer;
        }

        // "en_US", "da-DK", "zh-Hans_CN": the language is the first part, the region the last one of two letters.
        public static void Split(string id, out string language, out string region)
        {
            string[] parts = id.Split('_', '-');
            language = parts[0];
            region = parts.Length > 1 && parts[parts.Length - 1].Length == 2 ? parts[parts.Length - 1] : null;
        }

        // Windows' display language, and the country of the regional format (Settings > Time & language > Region).
        // JULE_LOCALE=en_US pretends to be that locale (for tests).
        static void SystemLocale(out string language, out string region)
        {
            string fake = Environment.GetEnvironmentVariable("JULE_LOCALE");
            if (!string.IsNullOrEmpty(fake)) { Split(fake, out language, out region); return; }
            language = null; region = null;
            try { language = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName; } catch { }
            try { region = RegionInfo.CurrentRegion.TwoLetterISORegionName; } catch { }
        }

        // The automatic choice on this machine. Read once: a change of language or region takes effect at the next start.
        static int auto;
        public static int Auto
        {
            get
            {
                if (auto == 0) { string l, r; SystemLocale(out l, out r); auto = Automatic(l, r); }
                return auto;
            }
        }

        // The setting's value as the folk to draw (0 or anything unknown = automatic).
        public static int Chosen(int setting) { return setting >= Nisser && setting <= Paekapikk ? setting : Auto; }

        // Test aid (--folk-test[=FILE]): what this machine's language and region give, and the rule for a list of
        // locales. Written to FILE (the exe has no console on Windows), or to the console without one.
        public static void Test(string file)
        {
            var lines = new List<string>();
            string l, r; SystemLocale(out l, out r);
            lines.Add("Denne maskine: sprog " + (l ?? "?") + ", region " + (r ?? "?") + " -> " + ShortNames[Auto - 1]);
            foreach (string id in new[] { "da_DK", "da_US", "en_DK", "nb_NO", "sv_SE", "fi_FI", "is_IS", "fo_FO", "kl_GL", "en_US", "en_GB",
                                          "de_DE", "de_AT", "en_DE", "da_DE", "fr_CH", "nl_NL", "nl_BE", "et_EE", "fr_FR", "es_MX", "pt_BR", "ja_JP",
                                          "zh-Hans_CN", "pl_PL", "en_AU" })
            {
                Split(id, out l, out r);
                lines.Add("  " + id.PadRight(11) + " " + ShortNames[Automatic(l, r) - 1]);
            }
            if (string.IsNullOrEmpty(file)) foreach (string line in lines) Console.WriteLine(line);
            else File.WriteAllLines(file, lines.ToArray());
        }
    }
}
