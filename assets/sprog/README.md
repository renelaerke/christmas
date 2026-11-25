# The menu's languages

Each file here is one language for JuleHygge's menu, on Windows, macOS and Linux alike. The app picks the
language of the user's machine when there is a file for it, and English otherwise. The menu "Sprog / Language"
lets the user choose another.

## The format

```
# a comment
@name = Deutsch
Snevejr = Schneefall
Høstak med fugleskræmsel (trin {0} af {1}) = Heuhaufen mit Vogelscheuche (Schritt {0} von {1})
```

- One text per line: the Danish text, ` = `, the text in this language.
- The Danish text on the left is the key. It must stay exactly as it is in the code, letter for letter.
- `{0}` and `{1}` stand for a number or a name the app puts in. Keep them.
- `@name` is the language's own name, as it is shown in the menu.
- The file is UTF-8 and is named after the language's two-letter code: `de.ini`, `fr.ini`.
- A text that is missing is shown in its language's file if the file is a regional variant, then in English, and
  last in Danish (see below).

`da.ini` only names the language: the app's own texts are Danish.

## A new language

1. Copy `en.ini` to `xx.ini` (`fr.ini` for French).
2. Change `@name` and translate the right-hand sides.
3. Add the file to `BUILT_IN` in `linux/src/lang.rs` (Windows and macOS pick up every file here by themselves).
4. Run `python3 tools/sprog-check.py`. It says what is missing or no longer matches.
5. If you can, add a front page in the language too: copy `README.en.md` at the top of the repository to
   `README.xx.md`, translate it, and add the language to the line of links at the top of every `README*.md`.

To try a language without building the app, put the file in a folder `sprog` beside the app's `settings.ini`
and restart the app. A file there also wins over the app's own file for the same language.

| | Where `settings.ini` is |
|---|---|
| Windows | `%APPDATA%\JuleHygge\` |
| macOS | `~/Library/Application Support/JuleHygge/` |
| Linux | `~/.config/JuleHygge/` |

## Regional variants and the fallback

A file can be one country's variant of a language: `es-MX.ini` is Spanish as spoken in Mexico. It holds only the
texts that differ (`Drage = Papalote`, `Julemanden = Santa Claus`); everything else comes from its language's file.
Every text is looked up down a chain, the usual way for translations, and the first file that has it wins:

```
es-MX.ini  →  es.ini  →  en.ini  →  the Danish text itself
de-AT.ini  →  de.ini  →  en.ini  →  …
```

The automatic choice follows the same order: a Mac, PC or desktop set to Spanish (Mexico) uses `es-MX.ini`; one set
to Spanish (Argentina) or Spanish (Spain), with no file of its own, uses `es.ini`; one set to a language with no
file at all uses English. So any variant of Spanish, German, French or another language falls back to that
language, as long as the language has a file.

A new variant: make `xx-YY.ini` (the language's code, a dash, the country's two letters), with `@name` (as in
`Español (México)`) and only the texts that differ. It needs the language's own `xx.ini`. Add it to `BUILT_IN` in
`linux/src/lang.rs` as `("xx-yy", include_str!(…))` and run the check.

## A new or changed text in the code

The Danish text in the code is the key, so changing it breaks its translations (the text is then shown in
Danish). When a menu text is added or changed, add or change it in `en.ini` and in every other file here, and run
the check.

## What is translated

The menu, its tooltips and the countdown. Not yet: the notifications, the advent calendar and its doors, and the
windows of JuleHygge Kamera.

The Swedish, German, Dutch, Italian, Spanish (and Mexican Spanish), French, Portuguese (and Brazilian Portuguese) and English texts were written by a language
model and have not been read by native speakers.
