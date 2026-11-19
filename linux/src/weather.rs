//! Changing weather (snow level 3, the default): the snow changes by itself between light snow, normal and
//! snowstorm over the day.
//!
//! Line for line the same as `src/Weather.cs` and `macos/Sources/JuleHygge/Weather.swift`, with the same random
//! numbers, so the day's weather is identical on Windows, macOS and Linux, after a restart and on every screen.
//! The day is a row of spells: light snow lasts 8-90 minutes, normal 6-70, a storm 4-25; short spells are the
//! most common. After light snow mostly normal, sometimes a storm; after a storm mostly normal, sometimes light.

use std::time::Instant;

use chrono::Datelike;

/// A spell starts `start` seconds after midnight and lasts until the next one. Level 0 light, 1 normal, 2 storm.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Spell {
    pub start: f64,
    pub level: i32,
}

/// The day's spells, in order; the first starts at midnight.
pub fn spells(year: i32, month: u32, day: u32) -> Vec<Spell> {
    let seed = (year * 10000 + month as i32 * 100 + day as i32) as u64;
    let mut state = seed.wrapping_mul(0x9E37_79B9_7F4A_7C15).wrapping_add(1);
    let mut result = Vec::new();
    let first = next(&mut state);
    let mut level = if first < 0.45 {
        0
    } else if first < 0.9 {
        1
    } else {
        2
    };
    let mut t = 0.0;
    while t < 86400.0 {
        result.push(Spell { start: t, level });
        let r = next(&mut state);
        // (r*r: most spells are short, a few are long)
        let minutes = match level {
            0 => 8.0 + 82.0 * r * r,
            1 => 6.0 + 64.0 * r * r,
            _ => 4.0 + 21.0 * r * r,
        };
        t += minutes * 60.0;
        let lot = next(&mut state);
        level = match level {
            0 => {
                if lot < 0.8 {
                    1
                } else {
                    2
                }
            }
            1 => {
                if lot < 0.65 {
                    0
                } else {
                    2
                }
            }
            _ => {
                if lot < 0.65 {
                    1
                } else {
                    0
                }
            }
        };
    }
    result
}

fn next(state: &mut u64) -> f64 {
    *state = state.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_407);
    (*state >> 40) as f64 / 16_777_216.0
}

/// Seconds the snow takes from one level to another: a storm builds up in 90 s and dies down over 3 minutes;
/// between light and normal it takes 4 minutes.
pub fn ramp(from: i32, to: i32) -> f64 {
    if to == 2 {
        90.0
    } else if from == 2 {
        180.0
    } else {
        240.0
    }
}

/// How much it snows `seconds` after midnight, gliding between levels (0 light ... 2 storm).
/// `before` is the level the day before ended on.
pub fn amount_at(spells: &[Spell], before: i32, seconds: f64) -> f64 {
    let Some(k) = spells.iter().rposition(|s| s.start <= seconds) else {
        return before as f64;
    };
    let now = spells[k].level;
    let was = if k > 0 { spells[k - 1].level } else { before };
    let t = ((seconds - spells[k].start) / ramp(was, now)).clamp(0.0, 1.0);
    was as f64 + (now - was) as f64 * (t * t * (3.0 - 2.0 * t))
}

/// The weather right now, looked up at most once a second.
pub struct Weather {
    cached: Option<(Instant, f64)>,
    /// JULE_WEATHER_TIME=HH:MM starts the day's weather at that time of day (the clock runs on from there),
    /// so a change can be watched without waiting for it. The macOS name JULE_VEJR_TID works too.
    start_at: Option<f64>,
    started: Instant,
}

impl Weather {
    pub fn new() -> Self {
        let start_at =
            std::env::var("JULE_WEATHER_TIME").or_else(|_| std::env::var("JULE_VEJR_TID")).ok().and_then(|v| {
                let (h, m) = v.trim().split_once(':')?;
                Some(h.parse::<f64>().ok()? * 3600.0 + m.parse::<f64>().ok()? * 60.0)
            });
        Weather { cached: None, start_at, started: Instant::now() }
    }

    /// 0 light ... 2 storm, gliding. JULE_DATE moves the date; the time of day is the real one.
    pub fn amount(&mut self) -> f64 {
        if let Some((at, a)) = self.cached {
            if at.elapsed().as_secs_f64() < 1.0 {
                return a;
            }
        }
        let today = crate::clock::today();
        let seconds = match self.start_at {
            Some(s) => (s + self.started.elapsed().as_secs_f64()) % 86400.0,
            None => crate::clock::seconds_of_day(),
        };
        let y = today.pred_opt().unwrap_or(today);
        let before = spells(y.year(), y.month(), y.day()).last().map(|s| s.level).unwrap_or(1);
        let a = amount_at(&spells(today.year(), today.month(), today.day()), before, seconds);
        self.cached = Some((Instant::now(), a));
        a
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Reference values computed with the C# code in src/Weather.cs (compiled with PowerShell's Add-Type,
    // 2026-11-18). If these fail, Linux no longer has the same weather as Windows and macOS.
    /// Date, number of spells, last spell's level, and the first five spells as (start second, level).
    type SpellCase = ((i32, u32, u32), usize, i32, [(f64, i32); 5]);

    #[test]
    fn same_spells_as_windows() {
        let cases: [SpellCase; 3] = [
            (
                (2026, 12, 1),
                57,
                1,
                [
                    (0.0, 0),
                    (2210.0514892966294, 1),
                    (6148.897901310743, 0),
                    (8711.331296905653, 2),
                    (8968.094945557224, 1),
                ],
            ),
            (
                (2026, 12, 24),
                59,
                1,
                [
                    (0.0, 1),
                    (1618.3119444214935, 2),
                    (2415.822770431437, 1),
                    (5301.612049411933, 0),
                    (6578.622026669398, 1),
                ],
            ),
            (
                (2027, 1, 15),
                50,
                0,
                [
                    (0.0, 0),
                    (5165.189250501225, 1),
                    (5594.962174117972, 2),
                    (6244.797250743951, 1),
                    (7362.293277886662, 0),
                ],
            ),
        ];
        for ((y, m, d), count, last, first) in cases {
            let s = spells(y, m, d);
            assert_eq!(s.len(), count, "{y}-{m}-{d} count");
            assert_eq!(s.last().unwrap().level, last, "{y}-{m}-{d} last level");
            for (i, (start, level)) in first.iter().enumerate() {
                assert!((s[i].start - start).abs() < 1e-9, "{y}-{m}-{d} spell {i} start {} vs {start}", s[i].start);
                assert_eq!(s[i].level, *level, "{y}-{m}-{d} spell {i} level");
            }
        }
    }

    #[test]
    fn same_amounts_as_windows() {
        let s = spells(2026, 12, 24);
        for (sec, want) in [
            (0.0, 1.0),
            (600.0, 1.0),
            (1650.0, 1.2846060874616902),
            (2500.0, 1.5484553849308667),
            (3600.5, 1.0),
            (43200.0, 2.0),
            (86000.0, 1.0),
        ] {
            let got = amount_at(&s, 1, sec);
            assert!((got - want).abs() < 1e-12, "amount at {sec}: {got} vs {want}");
        }
    }

    #[test]
    fn spells_cover_the_day() {
        for day in 1..=31 {
            let s = spells(2026, 12, day);
            assert_eq!(s[0].start, 0.0);
            assert!(s.windows(2).all(|w| w[0].start < w[1].start && w[0].level != w[1].level));
            assert!(s.iter().all(|x| (0..=2).contains(&x.level) && x.start < 86400.0));
        }
    }
}
