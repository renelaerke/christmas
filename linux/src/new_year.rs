//! New Year is the one theme with a moment: the countdown to midnight and the burst at the stroke
//! (`Controller.UpdateNewYear` in `src/Controller.cs`, `updateNewYear` in the macOS version). This keeps the time
//! it goes by and says when each thing is due; the controller does what is due (`Controller::update_new_year`).
//!
//! The clock is the computer's own, moved by the test aids: `JULE_DATE=2026-12-31` keeps the time of day on that
//! date, and `JULE_NYTAAR_OM=N` puts midnight N seconds after the app started.

use chrono::{Datelike, NaiveDate};

use crate::text;

/// What is due this frame.
#[derive(Debug, PartialEq)]
pub enum Moment {
    /// One of the last ten seconds: its number is written in sparks over the clock.
    Count(i32),
    /// The stroke of midnight: about a minute of the big effect starts.
    Midnight,
    /// The guests jump (now, and every nine seconds while the minute lasts).
    Jump,
    /// The new year's number is written once more.
    YearAgain,
}

pub struct NewYear {
    /// `JULE_NYTAAR_OM`: midnight is this many seconds after the app started.
    test_in: Option<f64>,
    last_left: f64,
    /// The minute of the burst lasts until this time (the app's clock).
    midnight_until: f64,
    year_again_at: Option<f64>,
    jump_at: Option<f64>,
    counted: i32,
    /// At midnight the tune waits for the bell's twelve strokes: until this time.
    pub tune_hold_until: f64,
    /// The menu's countdown line as last made, and when it is made again.
    pub countdown: String,
    countdown_at: f64,
}

/// Seconds to the next New Year's midnight on `today` at `seconds_of_day`; negative for the first hour of the new
/// year (the midnight that is counted down to stays for an hour after it has passed, then it is next year's).
pub fn left_at(today: NaiveDate, seconds_of_day: f64) -> f64 {
    if today.month() == 1 && today.day() == 1 && seconds_of_day < 3600.0 {
        return -seconds_of_day;
    }
    let next = NaiveDate::from_ymd_opt(today.year() + 1, 1, 1).unwrap_or(today);
    (next - today).num_days() as f64 * 86400.0 - seconds_of_day
}

/// The menu's countdown line: the days to New Year's Eve, on the day itself the hours and minutes to midnight, and
/// a greeting for the first hour of the new year.
pub fn countdown_text(left: f64) -> String {
    if left <= 0.0 {
        return text::new_year_greeting();
    }
    match (left / 86400.0).floor() as i64 {
        0 => {
            let minutes = (left / 60.0).ceil() as i64;
            text::new_year_midnight(minutes / 60, minutes % 60)
        }
        days => text::new_year_days(days),
    }
}

impl NewYear {
    pub fn new() -> NewYear {
        NewYear {
            test_in: std::env::var("JULE_NYTAAR_OM").ok().and_then(|v| v.trim().parse::<f64>().ok()),
            last_left: f64::INFINITY,
            midnight_until: -1.0,
            year_again_at: None,
            jump_at: None,
            counted: 0,
            tune_hold_until: -1.0,
            countdown: String::new(),
            countdown_at: 0.0,
        }
    }

    /// Seconds to midnight (negative for the hour after it), at the app's time `time`.
    pub fn left(&self, time: f64) -> f64 {
        match self.test_in {
            Some(n) => n - time,
            None => left_at(crate::clock::today(), crate::clock::seconds_of_day()),
        }
    }

    /// The year that begins at the midnight counted down to.
    pub fn year(&self, time: f64) -> i32 {
        let this = crate::clock::today().year();
        if self.test_in.is_some() || self.left(time) > 0.0 {
            this + 1
        } else {
            this
        }
    }

    /// What the clock shows: the hour hand's and the minute hand's turn (0..1 round the face), and the second
    /// hand's in the last minute before midnight; and a number that changes whenever a hand has moved enough to
    /// be drawn again (every minute; every second in the last one).
    pub fn hands(&self, time: f64) -> ((f64, f64, Option<f64>), i32) {
        let left = self.left(time);
        // (the time of day: midnight is a whole number of days away from the midnight counted down to)
        let tod = (86400.0 - left).rem_euclid(86400.0);
        let last_minute = left > 0.0 && left <= 60.0;
        let second = last_minute.then(|| (tod / 60.0).fract());
        let key = if last_minute { 100_000 + tod as i32 } else { (tod / 60.0) as i32 };
        (((tod / 43200.0).fract(), (tod / 3600.0).fract(), second), key)
    }

    /// The last ten minutes, and the minute of the burst: the guests stand round the clock.
    pub fn gather(&self, time: f64) -> bool {
        let left = self.left(time);
        (left > 0.0 && left <= 600.0) || time < self.midnight_until
    }

    /// The theme is not New Year (any more): nothing is counted, and nothing is carried over to the next time.
    pub fn rest(&mut self) {
        self.last_left = f64::INFINITY;
        self.midnight_until = -1.0;
    }

    /// The menu's countdown line, made anew once a second; true when it has changed.
    pub fn refresh_countdown(&mut self, time: f64) -> bool {
        if time < self.countdown_at {
            return false;
        }
        self.countdown_at = time + 1.0;
        let now = countdown_text(self.left(time));
        if now == self.countdown {
            return false;
        }
        self.countdown = now;
        true
    }

    /// What is due at the app's time `time` (called every frame while the theme is New Year).
    pub fn update(&mut self, time: f64) -> Vec<Moment> {
        let mut due = Vec::new();
        let left = self.left(time);
        // (after the computer has slept the time left has jumped: nothing is played late)
        let running = (self.last_left - left).abs() < 2.0;
        let second = left.ceil() as i32;
        if running && left > 0.0 && second <= 10 && second != self.counted {
            self.counted = second;
            due.push(Moment::Count(second));
        }
        if running && self.last_left > 0.0 && left <= 0.0 {
            self.midnight_until = time + 60.0;
            self.jump_at = Some(time);
            self.year_again_at = Some(time + 24.0);
            due.push(Moment::Midnight);
        }
        self.last_left = left;
        if time < self.midnight_until {
            if self.jump_at.is_some_and(|at| time >= at) {
                self.jump_at = Some(time + 9.0);
                due.push(Moment::Jump);
            }
            if self.year_again_at.is_some_and(|at| time >= at) {
                self.year_again_at = None;
                due.push(Moment::YearAgain);
            }
        }
        due
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day(y: i32, m: u32, d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, d).unwrap()
    }

    #[test]
    fn the_time_left_runs_to_midnight_and_stays_for_an_hour() {
        assert_eq!(left_at(day(2026, 12, 31), 86400.0 - 10.0), 10.0);
        assert_eq!(left_at(day(2026, 12, 31), 12.0 * 3600.0), 12.0 * 3600.0);
        assert_eq!(left_at(day(2026, 12, 30), 0.0), 2.0 * 86400.0);
        assert_eq!(left_at(day(2027, 1, 1), 5.0), -5.0);
        // an hour into the new year it is next year's midnight that is counted down to
        assert!(left_at(day(2027, 1, 1), 3600.0) > 364.0 * 86400.0);
    }

    #[test]
    fn the_countdown_and_midnight_come_once_each() {
        let mut n = NewYear::new();
        n.test_in = Some(15.0);
        let (mut counts, mut midnights, mut jumps, mut years) = (Vec::new(), 0, 0, 0);
        let mut t = 0.0;
        while t < 90.0 {
            for m in n.update(t) {
                match m {
                    Moment::Count(s) => counts.push(s),
                    Moment::Midnight => midnights += 1,
                    Moment::Jump => jumps += 1,
                    Moment::YearAgain => years += 1,
                }
            }
            if t > 6.0 && t < 15.0 {
                assert!(n.gather(t) && n.hands(t).0 .2.is_some(), "the guests gather and the second hand is there at {t}");
            }
            t += 0.05;
        }
        assert_eq!(counts, vec![10, 9, 8, 7, 6, 5, 4, 3, 2, 1]);
        assert_eq!((midnights, years), (1, 1));
        // (at midnight and every nine seconds of the minute after it)
        assert_eq!(jumps, 7);
        assert!(!n.gather(80.0), "the minute of the burst is over");
        // the hands stand at twelve at midnight
        let ((hour, minute, _), _) = n.hands(15.0);
        assert!(hour < 0.001 || hour > 0.999, "hour hand at {hour}");
        assert!(minute < 0.001 || minute > 0.999, "minute hand at {minute}");
    }

    #[test]
    fn nothing_is_played_late_after_a_sleep() {
        let mut n = NewYear::new();
        n.test_in = Some(100.0);
        assert!(n.update(0.0).is_empty());
        assert!(n.update(1.0).is_empty());
        // the frames stopped before midnight and came back after it
        assert!(n.update(130.0).is_empty(), "midnight passed while asleep: it is skipped");
    }
}
