//! Random numbers. Not for anything security related.
//! - `Rng` (xorshift64*) for the animation;
//! - `NetRandom`, .NET Framework's `System.Random`, for the sound synthesis, which seeds it with fixed numbers on
//!   Windows: with the same sequence the synthesized sounds come out the same as there.

pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        // xorshift must never hold 0
        let s = seed ^ 0x9E37_79B9_7F4A_7C15;
        Rng(if s == 0 { 1 } else { s })
    }

    /// Seeded from the clock and the process id, so every run differs.
    pub fn from_time() -> Self {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0);
        Rng::new(nanos ^ ((std::process::id() as u64) << 32))
    }

    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    /// 0 <= r < 1 (like `Random.NextDouble()` cast to float).
    pub fn f(&mut self) -> f32 {
        (self.next_u64() >> 40) as f32 / 16_777_216.0
    }

    /// 0 <= r < 1 as f64.
    pub fn f64(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / 9_007_199_254_740_992.0
    }

    /// lo <= r < hi (like `Random.Next(lo, hi)`); returns lo when the range is empty.
    pub fn range(&mut self, lo: i32, hi: i32) -> i32 {
        if hi <= lo {
            return lo;
        }
        lo + (self.next_u64() % (hi - lo) as u64) as i32
    }
}

/// .NET Framework's `System.Random(seed)` (Knuth's subtractive generator), as in its reference source.
pub struct NetRandom {
    seeds: [i32; 56],
    inext: usize,
    inextp: usize,
}

impl NetRandom {
    const MBIG: i32 = i32::MAX;
    const MSEED: i32 = 161_803_398;

    pub fn new(seed: i32) -> Self {
        let mut a = [0i32; 56];
        let subtraction = if seed == i32::MIN { i32::MAX } else { seed.abs() };
        let mut mj = Self::MSEED - subtraction;
        a[55] = mj;
        let mut mk = 1i32;
        for i in 1..55 {
            let ii = (21 * i) % 55;
            a[ii] = mk;
            mk = mj - mk;
            if mk < 0 {
                mk += Self::MBIG;
            }
            mj = a[ii];
        }
        for _ in 1..5 {
            for i in 1..56 {
                a[i] = a[i].wrapping_sub(a[1 + (i + 30) % 55]);
                if a[i] < 0 {
                    a[i] += Self::MBIG;
                }
            }
        }
        NetRandom { seeds: a, inext: 0, inextp: 21 }
    }

    fn internal_sample(&mut self) -> i32 {
        let mut next = self.inext + 1;
        if next >= 56 {
            next = 1;
        }
        let mut nextp = self.inextp + 1;
        if nextp >= 56 {
            nextp = 1;
        }
        let mut r = self.seeds[next].wrapping_sub(self.seeds[nextp]);
        if r == Self::MBIG {
            r -= 1;
        }
        if r < 0 {
            r += Self::MBIG;
        }
        self.seeds[next] = r;
        self.inext = next;
        self.inextp = nextp;
        r
    }

    /// `Random.NextDouble()`: 0 <= r < 1.
    pub fn next_double(&mut self) -> f64 {
        self.internal_sample() as f64 * (1.0 / Self::MBIG as f64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn net_random_is_repeatable_and_in_range() {
        let (mut a, mut b) = (NetRandom::new(42), NetRandom::new(42));
        let mut sum = 0.0;
        for _ in 0..100_000 {
            let x = a.next_double();
            assert_eq!(x, b.next_double());
            assert!((0.0..1.0).contains(&x));
            sum += x;
        }
        assert!((sum / 100_000.0 - 0.5).abs() < 0.01);
        assert_ne!(NetRandom::new(7).next_double(), NetRandom::new(42).next_double());
    }

    #[test]
    fn ranges_stay_inside() {
        let mut r = Rng::new(0);
        for _ in 0..10_000 {
            let a = r.f();
            assert!((0.0..1.0).contains(&a));
            let b = r.f64();
            assert!((0.0..1.0).contains(&b));
            let c = r.range(-50, 1970);
            assert!((-50..1970).contains(&c));
        }
        assert_eq!(r.range(5, 5), 5);
    }
}
