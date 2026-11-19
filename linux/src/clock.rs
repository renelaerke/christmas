//! The date the app believes it is (`JuleClock` in `src/Program.cs`).
//!
//! `JULE_DATE=yyyy-MM-dd` pretends it is another day, for testing the calendar, the snowman and the weather.
//! The time of day is always the real one.

use chrono::{Local, NaiveDate, Timelike};

pub fn today() -> NaiveDate {
    std::env::var("JULE_DATE")
        .ok()
        .and_then(|s| NaiveDate::parse_from_str(s.trim(), "%Y-%m-%d").ok())
        .unwrap_or_else(|| Local::now().date_naive())
}

/// Seconds since local midnight (real clock).
pub fn seconds_of_day() -> f64 {
    let now = Local::now();
    now.num_seconds_from_midnight() as f64 + now.nanosecond().min(999_999_999) as f64 / 1e9
}
