//! All user-facing text, in one place. It is Danish, like in the Windows and macOS versions (see AGENTS.md);
//! code, identifiers and comments are English. The menu's texts are shown in the user's language: the Danish text
//! here is the key to its translation (see `lang.rs` and `assets/sprog`), and the tray menu's helpers look it up. Where Windows says "proceslinjen" (the taskbar), Linux says
//! "panelet" (the panel).

/// Tray menu: quit the app.
pub const QUIT: &str = "Afslut";

/// Tray menu status and tooltip when no compositor runs, so the overlay cannot be see-through.
pub const NEEDS_COMPOSITOR: &str = "Kræver en compositor - sneen er slået fra";

/// Printed when a second copy is started.
pub const ALREADY_RUNNING: &str = "JuleHygge kører allerede.";

// ---------------------------------------------------------------------- tray menu
pub const MENU_CALENDAR: &str = "Julekalender...";
pub const MENU_SNOW: &str = "Snevejr";
pub const MENU_SNOW_LEVEL: &str = "Snemængde";
pub const SNOW_LEVELS: [&str; 4] = ["Let sne", "Normal", "Snestorm", "Skiftende vejr"];
pub const MENU_SNOW_GROUND: &str = "Sne på panelet";
pub const MENU_WINDOW_SNOW: &str = "Sne på vinduerne";
pub const MENU_SANTA: &str = "Julemanden";
pub const MENU_SEND_SANTA: &str = "Send julemanden afsted nu!";
pub const MENU_PLOW: &str = "Sneplov rydder panelet";
pub const MENU_SEND_PLOW: &str = "Send sneploven ud nu!";
pub const MENU_SOUND: &str = "Lyd: bjælder og jingle når julemanden flyver";
pub const MENU_PLOW_SOUND: &str = "Lyd: motor, skraben og horn fra sneploven";
pub const MENU_VOLUME: &str = "Lydstyrke";
pub const VOLUMES: [&str; 3] = ["Lav", "Middel", "Høj"];
// The walkers (see `folk.rs`): the two items are named after the folk that walks (indexed by `Folk::index`), and
// the choice between the folks.
pub const MENU_WALKERS: [&str; 5] = ["Nisser", "Alfer", "Wichtel", "Kabouters", "Päkapikud"];
pub const MENU_WALKER_COUNT: [&str; 5] = [
    "Antal nisser pr. skærm",
    "Antal alfer pr. skærm",
    "Antal Wichtel pr. skærm",
    "Antal kabouters pr. skærm",
    "Antal päkapikud pr. skærm",
];
pub const MENU_FOLK: &str = "Nisser eller alfer";
/// The menu's language (see `lang.rs`).
pub const MENU_LANGUAGE: &str = "Sprog";

/// The automatic language, with which one that is on this machine.
pub fn menu_language_automatic(name: &str) -> String {
    crate::lang::trf("Automatisk ({0})", &[name])
}
/// Indexed by `Folk::index`.
pub const FOLK: [&str; 5] =
    ["Nisser", "Alfer", "Wichtel (tyske nisser)", "Kabouters (hollandske nisser)", "Päkapikud (estiske nisser)"];

/// The automatic choice, with what it came to on this machine.
pub fn menu_folk_automatic(folk: &str) -> String {
    crate::lang::trf("Automatisk efter sprog og land ({0})", &[crate::lang::tr(folk).as_str()])
}
pub const MENU_POWER_SAVE: &str = "Strømspare";
/// Indexed by the `PowerSave` setting (0 off, 1 on, 2 only on battery).
pub const POWER_SAVE: [&str; 3] =
    ["Fra - normal billedfrekvens", "Til - færre billeder/s, stille blæser", "Kun når den bærbare kører på batteri"];
pub const MENU_FRAME_RATE: &str = "Billedfrekvens";
pub const FRAME_RATES: [&str; 4] = [
    "12 billeder/s - mindst strøm",
    "20 billeder/s - normal",
    "30 billeder/s - glattere sne",
    "60 billeder/s - mest strøm",
];
pub const MENU_LIGHTS: &str = "Julelys";
pub const MENU_ALL_SCREENS: &str = "Vis på alle skærme";
pub const MENU_PAUSE_FULLSCREEN: &str = "Pause ved fuldskærm (spil/film)";
pub const MENU_AUTOSTART: &str = "Start ved login";
pub const MENU_DEV_VERSION: &str = "Udviklerversion (opdaterer ikke)";
pub const MENU_AUTO_UPDATE: &str = "Opdatér automatisk";
pub const MENU_CHECK_UPDATE: &str = "Søg efter opdatering nu";

// ---------------------------------------------------------------------- the autumn theme (menu "Tema")
// The same menu in autumn: the items whose element has an autumn form get that form's name (as in the macOS and
// Windows versions).
pub const MENU_THEME: &str = "Tema";
pub const THEMES: [&str; 6] = ["Jul", "Efterår", "De dødes dag", "Halloween", "Nytår", "Karneval"];
pub const MENU_LEAVES: &str = "Løvfald";
pub const MENU_LEAF_LEVEL: &str = "Mængde af blade";
pub const LEAF_LEVELS: [&str; 4] = ["Få blade", "Normal", "Efterårsstorm", "Skiftende vejr"];
pub const MENU_LEAF_GROUND: &str = "Blade på panelet";
pub const MENU_WINDOW_LEAVES: &str = "Blade på vinduerne";
pub const MENU_GEESE: &str = "Trækgæs";
pub const MENU_SEND_GEESE: &str = "Send gæssene afsted nu!";
pub const MENU_GOOSE_SOUND: &str = "Lyd: gåsetræk når gæssene flyver";
pub const MENU_LEAF_COLLECTOR_SOUND: &str = "Lyd: motor, sug og horn fra løvsugeren";
pub const MENU_KITE: &str = "Drage";
pub const MENU_GARLAND: &str = "Løvranke med lygter";
pub const MENU_LEAF_COLLECTOR: &str = "Løvsuger rydder panelet";
pub const MENU_SEND_LEAF_COLLECTOR: &str = "Send løvsugeren ud nu!";
pub const MENU_ANIMALS: &str = "Pindsvin og egern";
pub const MENU_ANIMAL_COUNT: &str = "Antal dyr pr. skærm";
pub const NOTICE_SCARECROW_TITLE: &str = "Høstakken vokser!";

// ---------------------------------------------------------------------- De dødes dag (menu "Tema")
// The same menu on the Day of the Dead (as in the macOS and Windows versions): marigold petals for snow, an ofrenda
// for the snowman, monarch butterflies for Santa, calacas for the nisser, papel picado for the lights and a donkey
// cart for the plow.
pub const MENU_PETALS: &str = "Kronblade fra tagetes";
pub const MENU_PETAL_LEVEL: &str = "Mængde af kronblade";
pub const PETAL_LEVELS: [&str; 4] = ["Få kronblade", "Normal", "Kronbladsstorm", "Skiftende vejr"];
pub const MENU_PETAL_GROUND: &str = "Tagetes-tæppe på panelet";
pub const MENU_WINDOW_PETALS: &str = "Kronblade på vinduerne";
pub const MENU_BUTTERFLIES: &str = "Monarksommerfugle";
pub const MENU_SEND_BUTTERFLIES: &str = "Send sommerfuglene afsted nu!";
pub const MENU_BUTTERFLY_SOUND: &str = "Lyd: guitar og marimba når sommerfuglene flyver";
pub const MENU_CART_SOUND: &str = "Lyd: hovtramp, hjulknirk og æselbrøl fra æselkærren";
pub const MENU_PICADO: &str = "Papel picado";
pub const MENU_CART: &str = "Æselkærre samler kronbladene";
pub const MENU_SEND_CART: &str = "Send æselkærren ud nu!";
pub const MENU_CALACAS: &str = "Calacas (skeletter)";
pub const MENU_CALACA_COUNT: &str = "Antal calacas pr. skærm";
pub const NOTICE_OFRENDA_TITLE: &str = "Ofrendaen er færdig!";
pub const FRAME_RATES_MUERTOS: [&str; 4] = [
    "12 billeder/s - mindst strøm",
    "20 billeder/s - normal",
    "30 billeder/s - glattere kronbladsfald",
    "60 billeder/s - mest strøm",
];

pub fn menu_ofrenda(stage: i32, max: i32) -> String {
    crate::lang::trf("Ofrenda (alter) (trin {0} af {1})", &[stage.to_string().as_str(), max.to_string().as_str()])
}

/// The notice when the ofrenda's last step is in place (it grows a step for every hour the app runs).
pub fn notice_ofrenda() -> String {
    "Calacas har pyntet alteret. Til sidst kom der et glas vand, et lille sukkerkranie og en monarksommerfugl - ofrendaen er færdig!"
        .to_string()
}

// ---------------------------------------------------------------------- New Year (menu "Tema")
// The same menu at New Year (as in the macOS and Windows versions): confetti for the snow, a decorated clock for the
// snowman, rockets for Santa, party guests for the nisser, pennants and paper lanterns for the lights, and a street
// sweeper for the plow. The countdown line stays: here it counts down to midnight.
pub const MENU_CONFETTI: &str = "Konfetti";
pub const MENU_CONFETTI_LEVEL: &str = "Mængde af konfetti";
pub const CONFETTI_LEVELS: [&str; 4] = ["Lidt konfetti", "Normal", "Konfettistorm", "Skiftende vejr"];
pub const MENU_CONFETTI_GROUND: &str = "Konfetti på panelet";
pub const MENU_WINDOW_PARTY: &str = "Konfetti, stjernekastere og bordbomber på vinduerne";
pub const MENU_ROCKETS: &str = "Raketter";
pub const MENU_SEND_ROCKETS: &str = "Send raketter op nu!";
pub const MENU_ROCKET_SOUND: &str = "Lyd: melodi til raketterne og klokkeslag ved midnat";
pub const MENU_SWEEPER: &str = "Fejemaskine rydder konfettien";
pub const MENU_SEND_SWEEPER: &str = "Send fejemaskinen ud nu!";
pub const MENU_STREET_SWEEPER_SOUND: &str = "Lyd: motor og sug fra fejemaskinen";
pub const MENU_GUESTS: &str = "Festgæster";
pub const MENU_GUEST_COUNT: &str = "Antal gæster pr. skærm";
pub const MENU_PARTY_GARLAND: &str = "Vimpler og papirlanterner";
pub const FRAME_RATES_NEW_YEAR: [&str; 4] = [
    "12 billeder/s - mindst strøm",
    "20 billeder/s - normal",
    "30 billeder/s - glattere konfetti",
    "60 billeder/s - mest strøm",
];
pub const NOTICE_CLOCK_TITLE: &str = "Uret er pyntet færdigt!";

pub fn menu_clock(stage: i32, max: i32) -> String {
    crate::lang::trf("Ur med pynt (trin {0} af {1})", &[stage.to_string().as_str(), max.to_string().as_str()])
}

/// The notice when the last of the clock's decorations is in place (a step for every hour the app runs).
pub fn notice_clock() -> String {
    "Gæsterne har pyntet det. Til sidst kom der to stjernekastere - uret er pyntet færdigt!".to_string()
}

/// The countdown line at New Year: a greeting for the first hour of the new year,
pub fn new_year_greeting() -> String {
    crate::lang::tr("★ Godt nytår! ★")
}

/// ... the days to New Year's Eve,
pub fn new_year_days(days: i64) -> String {
    match days {
        1 => crate::lang::tr("★ 1 dag til nytårsaften ★"),
        d => crate::lang::trf("★ {0} dage til nytårsaften ★", &[d.to_string().as_str()]),
    }
}

/// ... and on the day itself the hours and minutes to midnight.
pub fn new_year_midnight(hours: i64, minutes: i64) -> String {
    crate::lang::trf("★ {0}:{1} til midnat ★", &[hours.to_string().as_str(), format!("{minutes:02}").as_str()])
}

// ---------------------------------------------------------------------- Carnival (menu "Tema")
// The same menu at carnival (as in the macOS and Windows versions): confetti and feathers for the snow, a carnival
// float for the snowman, a band truck for Santa, a samba parade for the nisser, a fringe garland with masks behind
// the lights, and street sweepers for the plow. The amount of confetti, the confetti on the panel and the frame
// rates keep New Year's texts. No calendar, no countdown and no choice of folk; instead the choice of which
// carnival: each text is first Rio's, then the Rhineland's (indexed by the carnival's number less one).
pub const MENU_CARNIVAL: &str = "Karneval fra";
pub const CARNIVALS: [&str; 2] = ["Rio (Brasilien)", "Rhinlandet (Tyskland)"];
pub const MENU_CARNIVAL_FALL: [&str; 2] = ["Konfetti og fjer", "Konfetti og karameller"];
pub const MENU_WINDOW_CARNIVAL: [&str; 2] =
    ["Konfetti og tukaner på vinduerne", "Konfetti, narrehuer og berlinere på vinduerne"];
pub const MENU_BAND_TRUCK: [&str; 2] = ["Orkesterbil", "Festvogn"];
pub const MENU_SEND_BAND_TRUCK: [&str; 2] = ["Send orkesterbilen afsted nu!", "Send festvognen afsted nu!"];
pub const MENU_BAND_SOUND: [&str; 2] =
    ["Lyd: sambatrommer når orkesterbilen kører", "Lyd: hornorkester når festvognen kører"];
pub const MENU_STREET_SWEEPERS: &str = "Gadefejere rydder konfettien";
pub const MENU_SEND_STREET_SWEEPERS: &str = "Send gadefejerne ud nu!";
pub const MENU_BROOM_SOUND: &str = "Lyd: koste når gadefejerne fejer";
pub const MENU_PARADE: [&str; 2] = ["Sambaoptog", "Karnevalsoptog"];
pub const MENU_PARADE_COUNT: [&str; 2] = ["Antal dansere pr. skærm", "Antal narre pr. skærm"];
pub const MENU_CARNIVAL_GARLAND: [&str; 2] = ["Frynseguirlande med masker", "Vimpler og narrehuer"];
pub const NOTICE_FLOAT_TITLE: &str = "Karnevalsvognen er færdig!";
pub const NOTICE_PRUNKWAGEN_TITLE: &str = "Pragtvognen er færdig!";
pub const NOTICE_PRUNKWAGEN: &str = "Narrene har bygget den.";

/// The float's item, with how far it has come (`rhein`: the Rhineland's float).
pub fn menu_float(rhein: bool, stage: i32, max: i32) -> String {
    let text = if rhein { "Pragtvogn (trin {0} af {1})" } else { "Karnevalsvogn (trin {0} af {1})" };
    crate::lang::trf(text, &[stage.to_string().as_str(), max.to_string().as_str()])
}

/// The notice when the last of the float's steps is in place (a step for every hour the app runs).
pub fn notice_float(step: &str) -> String {
    format!("Sambaskolen har bygget den. Til sidst kom der {step}")
}

/// What the float got at each step (1..=12): it is built from the wheels up.
pub const FLOAT_STEPS: [&str; 12] = [
    "et chassis på hjul",
    "et nederste dæk",
    "et skørt med frynser",
    "et øverste dæk og en trappe",
    "guldkanter",
    "to søjler",
    "en stor sol",
    "solens stråler",
    "solens ansigt",
    "vifter af fjer",
    "kulørte pærer",
    "serpentiner og vimpler - vognen er færdig!",
];

// ---------------------------------------------------------------------- Halloween (menu "Tema")
// The same menu on Halloween (as in the macOS and Windows versions). The leaves are autumn's and keep autumn's
// names; the rest: jack-o'-lanterns for the snowman, a witch for Santa, ghosts and children dressed up for the
// nisser, a string of pumpkins and bats for the lights, and a witch or ghosts for the plow.
pub const MENU_WINDOW_SPOOKS: &str = "Blade, katte og edderkopper på vinduerne";
pub const MENU_WITCH: &str = "Heks på kost";
pub const MENU_SEND_WITCH: &str = "Send heksen afsted nu!";
pub const MENU_WITCH_SOUND: &str = "Lyd: uhyggelig melodi når heksen flyver";
pub const MENU_SWEEPERS: &str = "Heks eller spøgelser rydder bladene";
pub const MENU_SEND_SWEEPERS: &str = "Send dem ud nu!";
pub const MENU_SWEEPER_SOUND: &str = "Lyd: kost eller spøgelsessus når bladene ryddes";
pub const MENU_SPOOKS: &str = "Spøgelser og udklædte børn";
pub const MENU_SPOOK_COUNT: &str = "Antal spøgelser pr. skærm";
pub const MENU_SPOOK_GARLAND: &str = "Lyskæde med græskar og flagermus";
pub const NOTICE_PUMPKINS_TITLE: &str = "Græskarlygterne er færdige!";

pub fn menu_pumpkins(stage: i32, max: i32) -> String {
    crate::lang::trf("Græskarlygter (trin {0} af {1})", &[stage.to_string().as_str(), max.to_string().as_str()])
}

/// The notice when the last of the jack-o'-lanterns' steps is in place (a step for every hour the app runs).
pub fn notice_pumpkins() -> String {
    "Spøgelserne har skåret dem ud. Til sidst kom der en sort kat - græskarlygterne er færdige!".to_string()
}

pub fn menu_scarecrow(stage: i32, max: i32) -> String {
    crate::lang::trf("Høstak med fugleskræmsel (trin {0} af {1})", &[stage.to_string().as_str(), max.to_string().as_str()])
}

pub fn notice_scarecrow(step: &str) -> String {
    format!("Pindsvinene og egernene har bygget videre. I dag kom der {step}")
}

/// What the haystack and the scarecrow got on each day (stage 1..=12).
pub const SCARECROW_STEPS: [&str; 12] = [
    "en lille bunke hø",
    "mere hø",
    "en hel høstak",
    "en stolpe til fugleskræmslet",
    "en tværpind til armene",
    "et hoved af sækkelærred",
    "en ternet skjorte",
    "hænder af halm",
    "et ansigt",
    "et grønt halstørklæde",
    "en stråhat",
    "et græskar og en krage - fugleskræmslet er færdigt!",
];
pub const FRAME_RATES_AUTUMN: [&str; 4] = [
    "12 billeder/s - mindst strøm",
    "20 billeder/s - normal",
    "30 billeder/s - glattere løvfald",
    "60 billeder/s - mest strøm",
];

pub fn menu_version(v: &str) -> String {
    crate::lang::trf("Version {0}", &[v])
}

/// (The Christmas snowman has no stage: the children build it while you watch. Autumn's haystack has, see
/// `menu_scarecrow`.)
pub const MENU_SNOWMAN: &str = "Snemand";

/// "★ 12 dage til juleaften ★" for the given number of days.
pub fn countdown(days: i64) -> String {
    match days {
        0 => crate::lang::tr("★ Glædelig jul! ★"),
        1 => crate::lang::tr("★ 1 dag til juleaften ★"),
        d => crate::lang::trf("★ {0} dage til juleaften ★", &[d.to_string().as_str()]),
    }
}

// ---------------------------------------------------------------------- notifications
pub const NOTICE_STARTED_TITLE: &str = "Jule-hygge er tændt";
pub const NOTICE_STARTED: &str =
    "Klik på snefnugget i panelet for julekalenderen. Højreklik for indstillinger og for at kalde på julemanden!";
pub const NOTICE_DOOR_TITLE: &str = "Dagens låge er klar!";
/// The action on the door notice (shown as a button by some desktops).
pub const NOTICE_OPEN_CALENDAR: &str = "Åbn kalenderen";

pub const NOTICE_UPDATED_TITLE: &str = "Jule-hygge er opdateret";
pub const NOTICE_UPDATE_TITLE: &str = "Opdatering";

pub fn notice_updated(v: &str) -> String {
    format!("Du kører nu version {v}.")
}

pub fn notice_up_to_date(v: &str) -> String {
    format!("Du har den nyeste version ({v}).")
}

pub fn notice_update_failed(e: &str) -> String {
    format!("Kunne ikke opdatere: {e}")
}

pub fn notice_install_failed(v: &str, e: &str) -> String {
    format!("Kunne ikke installere version {v}: {e}")
}

pub fn notice_door(day: u32) -> String {
    format!("Låge {day} i julekalenderen venter på dig. Klik her for at åbne kalenderen.")
}

// ---------------------------------------------------------------------- calendar
pub fn calendar_title(year: i32) -> String {
    format!("Julekalender {year}")
}

pub fn calendar_opens_in(days: i64) -> String {
    let unit = if days == 1 { "dag" } else { "dage" };
    format!("Julekalenderen åbner den 1. december, om {days} {unit}. Indtil da må du nøjes med nisserne!")
}

pub fn calendar_todays_door(day: u32) -> String {
    format!("Dagens låge er nummer {day}. Kan du finde den?")
}

pub const CALENDAR_READ_AGAIN: &str = "Klik på en åben låge for at læse den igen.";

pub fn calendar_door(day: i32, text: &str) -> String {
    format!("Låge {day}:  {text}")
}

pub fn calendar_patience(day: i32, days: i64) -> String {
    let unit = if days == 1 { "dag." } else { "dage." };
    format!("Tålmodighed! Låge {day} kan åbnes om {days} {unit}")
}

pub fn calendar_opens_on(day: i32) -> String {
    format!("Låge {day} åbner den {day}. december.")
}

/// Behind each door. The facts are not source-checked (see AGENTS.md); check them before adding new ones.
pub const DOOR_TEXTS: [&str; 24] = [
    /* 1 */ "Velkommen til december! Nisserne er klar og vinker til dig fra panelet. Kan du se dem?",
    /* 2 */ "Hvad kalder man en snemand om sommeren? En vandpyt!",
    /* 3 */ "Hyggetip: Tænd et lys, lav en kop varm kakao og hold fem minutters pause. Arbejdet kan godt vente lidt.",
    /* 4 */ "Vidste du, at julemærket blev fundet på af den danske postmand Einar Holbøll? Det første kom i 1904.",
    /* 5 */ "Hvorfor er julemanden så god til karate? Fordi han har sort bælte!",
    /* 6 */ "Hyggetip: Send en julehilsen til én, du ikke har talt med længe. Det tager to minutter og gør dagen bedre for jer begge.",
    /* 7 */ "Vidste du, at det første kendte juletræ i Danmark blev tændt på Holsteinborg gods i 1808?",
    /* 8 */ "Vejrudsigten for i dag: Kraftigt snefald over skrivebordet. Find vanterne frem!",
    /* 9 */ "Hvad sagde den ene snemand til den anden? \"Kan du også lugte gulerødder?\"",
    /* 10 */ "Hyggetip: Gå en tur, når det bliver mørkt, og kig efter julelys i vinduerne.",
    /* 11 */ "I gamle dage boede nissen på gården. Fik han ikke sin risengrød juleaften, lavede han ballade. Nisserne her på skærmen er heldigvis nemmere at gøre glade.",
    /* 12 */ "Halvvejs til juleaften! Julemanden tager en ekstra prøvetur for at fejre det. Hold øje med himlen.",
    /* 13 */ "I dag er det Santa Lucia. Lyset fejres med optog og hvide kjoler. Her på skærmen fejrer vi det med et stjerneskud.",
    /* 14 */ "Hvad får man, hvis man krydser en snemand med en vampyr? Frostbid!",
    /* 15 */ "Hyggetip: Bag pebernødder. Dejen tager ti minutter, og hele huset kommer til at dufte af jul.",
    /* 16 */ "Vidste du, at Rudolf med den røde tud blev opfundet i 1939 til en lille julebog fra et amerikansk stormagasin?",
    /* 17 */ "Snestorm! Godt at du sidder indenfor i varmen.",
    /* 18 */ "Hvad siger man til en nisse, der er ked af det? Op med humøret, og op med huen!",
    /* 19 */ "Hyggetip: Sæt julemusik på og ryd op på skrivebordet. Både det rigtige og det her på skærmen.",
    /* 20 */ "Vidste du, at risalamande er dansk, selvom navnet lyder fransk? Det kommer af \"riz à l'amande\", som betyder ris med mandler.",
    /* 21 */ "Nisserne holder generalprøve på dansen om juletræet. Se dem lige vinke!",
    /* 22 */ "Hyggetip: Skriv en ønskeseddel, også selvom du er voksen. Julemanden flyver forbi lige om lidt og kan måske nå at tage den med.",
    /* 23 */ "Lillejuleaften! Husk at gemme en hel mandel til risalamanden. Den, der finder den, får mandelgaven.",
    /* 24 */ "Glædelig jul! I Danmark holder vi jul om aftenen den 24., mens mange andre lande først fejrer den den 25. om morgenen. Julemanden er på vej, så god jul og godt nytår!",
];
