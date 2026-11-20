using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;

namespace JuleHygge
{
    class Settings
    {
        public bool Snow = true, SnowGround = true, Santa = true, Nisser = true, Lights = true,
                    PauseFullscreen = true, Snowman = true, AllScreens = true, Plow = true, WindowSnow = true;
        public bool Sound = false, PlowSound = false;   // sound is always off by default
        public int SnowLevel = 3;          // 0 = let, 1 = normal, 2 = snestorm, 3 = skiftende vejr (Weather), som er standard
        public int NisseCount = 3;         // pr. skærm
        public int PowerSave = 2;          // 0 = off, 1 = always on, 2 = only on battery
        public int SoundLevel = 1;         // 0 = low, 1 = medium, 2 = high
        public int FrameRate = 20;         // frames/s while the scene is calm: 12, 20, 30 or 60 (same default as macOS)
        public int Theme = 0;              // 0 = jul, 1 = efterår (as macOS; see Controller.Autumn)
        public bool Kite = true;           // autumn's kite over the primary screen
        public int Folk = 0;               // 0 = automatic by language and region, else 1 nisser, 2 alfer, 3 Wichtel, 4 kabouters, 5 päkapikud (class Folk)
        public bool AutoUpdate = true;     // install new GitHub releases by itself
        public string LastVersion = "";  // the version that ran last time, to announce an update
        public int SnowmanSeenStage = 0;
        public int CalendarYear = 0;
        public DateTime FirstRun = DateTime.MinValue, LastDoorNotice = DateTime.MinValue;
        public HashSet<int> OpenedDoors = new HashSet<int>();

        // JULE_SETTINGS=<path> uses another file, so tests never touch the real settings.
        static string FilePath
        {
            get
            {
                string over = Environment.GetEnvironmentVariable("JULE_SETTINGS");
                if (!string.IsNullOrEmpty(over)) return Path.GetFullPath(over);
                return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "JuleHygge", "settings.ini");
            }
        }

        public static Settings Load()
        {
            var s = new Settings();
            var d = new Dictionary<string, string>();
            // The file can be briefly locked (OneDrive, antivirus), so retry a few times. If it still
            // cannot be read, run on defaults but never save, so the user's real file is not overwritten.
            if (File.Exists(FilePath))
            {
                s.loadFailed = true;
                for (int attempt = 0; attempt < 5 && s.loadFailed; attempt++)
                {
                    try
                    {
                        d.Clear();
                        foreach (var line in File.ReadAllLines(FilePath))
                        {
                            int i = line.IndexOf('=');
                            if (i > 0) d[line.Substring(0, i).Trim()] = line.Substring(i + 1).Trim();
                        }
                        s.loadFailed = false;
                    }
                    catch (IOException) { System.Threading.Thread.Sleep(200); }
                    catch (UnauthorizedAccessException) { System.Threading.Thread.Sleep(200); }
                }
            }

            s.Snow = B(d, "Snow", s.Snow);
            s.SnowGround = B(d, "SnowGround", s.SnowGround);
            s.Santa = B(d, "Santa", s.Santa);
            s.Nisser = B(d, "Nisser", s.Nisser);
            s.Lights = B(d, "Lights", s.Lights);
            s.PauseFullscreen = B(d, "PauseFullscreen", s.PauseFullscreen);
            s.Snowman = B(d, "Snowman", s.Snowman);
            s.AllScreens = B(d, "AllScreens", s.AllScreens);
            s.Plow = B(d, "Plow", s.Plow);
            s.WindowSnow = B(d, "WindowSnow", s.WindowSnow);
            s.Sound = B(d, "Sound", s.Sound);
            s.PlowSound = B(d, "PlowSound", s.PlowSound);
            s.SoundLevel = Math.Max(0, Math.Min(2, I(d, "SoundLevel", s.SoundLevel)));
            s.FrameRate = I(d, "FrameRate", s.FrameRate);
            if (Array.IndexOf(new[] { 12, 20, 30, 60 }, s.FrameRate) < 0) s.FrameRate = 20;
            s.Theme = I(d, "Theme", 0) == 1 ? 1 : 0;
            s.Kite = B(d, "Kite", s.Kite);
            s.Folk = Math.Max(0, Math.Min(5, I(d, "Folk", s.Folk)));
            s.SnowLevel = Math.Max(0, Math.Min(3, I(d, "SnowLevel", s.SnowLevel)));
            s.NisseCount = Math.Max(1, Math.Min(12, I(d, "NisseCount", s.NisseCount)));
            s.PowerSave = Math.Max(0, Math.Min(2, I(d, "PowerSave", s.PowerSave)));
            s.AutoUpdate = B(d, "AutoUpdate", s.AutoUpdate);
            string lv; if (d.TryGetValue("LastVersion", out lv)) s.LastVersion = lv;
            s.SnowmanSeenStage = I(d, "SnowmanSeenStage", 0);
            s.CalendarYear = I(d, "CalendarYear", 0);
            s.FirstRun = D(d, "FirstRun");
            s.LastDoorNotice = D(d, "LastDoorNotice");
            string od;
            if (d.TryGetValue("OpenedDoors", out od))
                foreach (var part in od.Split(','))
                {
                    int n;
                    if (int.TryParse(part, out n) && n >= 1 && n <= 24) s.OpenedDoors.Add(n);
                }
            return s;
        }

        bool loadFailed;

        public void Save()
        {
            if (loadFailed) return;
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(FilePath));
                // Write to a temp file first and swap it in, so a crash mid-write never leaves a half file.
                string tmp = FilePath + ".tmp";
                File.WriteAllLines(tmp, new[] {
                    "Snow=" + B(Snow), "SnowGround=" + B(SnowGround), "Santa=" + B(Santa),
                    "Nisser=" + B(Nisser), "Lights=" + B(Lights), "PauseFullscreen=" + B(PauseFullscreen),
                    "Snowman=" + B(Snowman), "AllScreens=" + B(AllScreens), "Plow=" + B(Plow), "WindowSnow=" + B(WindowSnow), "Sound=" + B(Sound), "PlowSound=" + B(PlowSound), "SoundLevel=" + SoundLevel,
                    "SnowLevel=" + SnowLevel, "NisseCount=" + NisseCount, "PowerSave=" + PowerSave, "FrameRate=" + FrameRate, "Theme=" + Theme, "Kite=" + B(Kite), "Folk=" + Folk, "AutoUpdate=" + B(AutoUpdate), "LastVersion=" + LastVersion,
                    "SnowmanSeenStage=" + SnowmanSeenStage, "CalendarYear=" + CalendarYear,
                    "FirstRun=" + Ds(FirstRun), "LastDoorNotice=" + Ds(LastDoorNotice),
                    "OpenedDoors=" + string.Join(",", OpenedDoors.OrderBy(x => x)) });
                if (File.Exists(FilePath)) File.Replace(tmp, FilePath, null);
                else File.Move(tmp, FilePath);
            }
            catch { }
        }

        static string B(bool b) { return b ? "1" : "0"; }
        static string Ds(DateTime d) { return d == DateTime.MinValue ? "" : d.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture); }

        static bool B(Dictionary<string, string> d, string k, bool def)
        {
            string v;
            return d.TryGetValue(k, out v) ? v == "1" : def;
        }
        static int I(Dictionary<string, string> d, string k, int def)
        {
            string v; int n;
            return d.TryGetValue(k, out v) && int.TryParse(v, out n) ? n : def;
        }
        static DateTime D(Dictionary<string, string> d, string k)
        {
            string v; DateTime t;
            if (d.TryGetValue(k, out v) && DateTime.TryParseExact(v, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out t))
                return t;
            return DateTime.MinValue;
        }
    }
}
