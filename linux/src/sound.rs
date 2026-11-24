//! Synthesized sound effects (the project has no sound files): Santa's sleigh bells with one of three public-domain
//! tunes, and the snow plow's engine, scraping and horn. Ported from `src/Sound.cs` (itself from macOS `Sound.swift`);
//! the noise uses .NET's `Random` with the same seeds, so the samples come out as on Windows.
//!
//! Playback goes through `cpal` (ALSA, which reaches PipeWire and PulseAudio through their ALSA plugins). The
//! playback thread only exists while something is audible, so sound costs nothing the rest of the time. Sound is
//! always off by default.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::JoinHandle;
use std::time::Duration;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

use crate::rng::NetRandom;

pub const SAMPLE_RATE: u32 = 44_100;

type Maker = Box<dyn Fn() -> Vec<f32> + Send + Sync>;

/// One sound: a looping buffer whose volume and pan follow something on screen, or a one-shot.
struct VoiceState {
    make: Arc<Maker>,
    samples: Arc<OnceLock<Vec<f32>>>,
    generating: Arc<AtomicBool>,
    loops: bool,
    playing: bool,
    /// Fractional, so the voice can play faster or slower than recorded.
    pos: f64,
    gain: f32,
    pan: f32,
    applied_gain: f32,
    applied_pan: f32,
    /// Playback speed, tempo and pitch together (like a tape): Santa's tune follows his pace.
    rate: f32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Voice(usize);

pub struct AudioHub {
    voices: Arc<Mutex<Vec<VoiceState>>>,
    thread: Option<JoinHandle<()>>,
    stop: Arc<AtomicBool>,
    quiet_since: Option<f64>,
}

impl AudioHub {
    pub fn new() -> AudioHub {
        AudioHub {
            voices: Arc::new(Mutex::new(Vec::new())),
            thread: None,
            stop: Arc::new(AtomicBool::new(false)),
            quiet_since: None,
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Vec<VoiceState>> {
        self.voices.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn create_voice(&mut self, make: impl Fn() -> Vec<f32> + Send + Sync + 'static, loops: bool) -> Voice {
        let mut v = self.lock();
        v.push(VoiceState {
            make: Arc::new(Box::new(make)),
            samples: Arc::new(OnceLock::new()),
            generating: Arc::new(AtomicBool::new(false)),
            loops,
            playing: false,
            pos: 0.0,
            gain: 0.0,
            pan: 0.0,
            applied_gain: 0.0,
            applied_pan: 0.0,
            rate: 1.0,
        });
        Voice(v.len() - 1)
    }

    /// The sound is synthesized in the background the first time it is needed (it takes up to a second).
    /// Returns true when it is ready.
    pub fn warm(&self, v: Voice) -> bool {
        let s = &self.lock()[v.0];
        if s.samples.get().is_some() {
            return true;
        }
        if !s.generating.swap(true, Ordering::SeqCst) {
            let (make, samples) = (s.make.clone(), s.samples.clone());
            let _ = std::thread::Builder::new().name("synth".into()).spawn(move || {
                let _ = samples.set(make());
            });
        }
        false
    }

    pub fn playing(&self, v: Voice) -> bool {
        self.lock()[v.0].playing
    }

    pub fn set_rate(&self, v: Voice, rate: f32) {
        self.lock()[v.0].rate = rate.clamp(0.5, 2.0);
    }

    /// Looping voice: fades smoothly (about half a second) toward `level` (0..1) and pans to `pan` (-1..1).
    pub fn update(&mut self, v: Voice, level: f32, pan: f32, dt: f32) {
        let pan = pan.clamp(-1.0, 1.0);
        if level > 0.0 && !self.playing(v) {
            if !self.warm(v) {
                return;
            }
            let mut voices = self.lock();
            let s = &mut voices[v.0];
            s.pos = 0.0;
            s.gain = 0.0;
            s.applied_gain = 0.0;
            s.pan = pan;
            s.applied_pan = pan;
            s.playing = true;
            drop(voices);
            self.ensure_running();
        }
        let mut voices = self.lock();
        let s = &mut voices[v.0];
        if !s.playing {
            return;
        }
        s.gain += (level - s.gain) * (dt * 4.0).min(1.0);
        s.pan = pan;
        if level == 0.0 && s.gain < 0.003 {
            s.playing = false;
            s.gain = 0.0;
            s.applied_gain = 0.0;
        }
    }

    /// Plays the whole buffer once.
    pub fn play_once(&mut self, v: Voice, level: f32, pan: f32) {
        if !self.warm(v) {
            return;
        }
        let mut voices = self.lock();
        let s = &mut voices[v.0];
        s.pos = 0.0;
        s.gain = level;
        s.applied_gain = level;
        s.pan = pan.clamp(-1.0, 1.0);
        s.applied_pan = s.pan;
        s.playing = true;
        drop(voices);
        self.ensure_running();
    }

    /// Called once per frame: stops the playback thread after a second of silence.
    pub fn idle_check(&mut self, now: f64) {
        if self.thread.is_none() {
            return;
        }
        if self.lock().iter().any(|v| v.playing) {
            self.quiet_since = None;
            return;
        }
        let since = *self.quiet_since.get_or_insert(now);
        if now - since > 1.0 {
            self.stop_all();
        }
    }

    pub fn stop_all(&mut self) {
        for v in self.lock().iter_mut() {
            v.playing = false;
            v.gain = 0.0;
            v.applied_gain = 0.0;
        }
        if let Some(t) = self.thread.take() {
            self.stop.store(true, Ordering::SeqCst);
            let _ = t.join();
        }
        self.quiet_since = None;
    }

    fn ensure_running(&mut self) {
        if self.thread.is_some() {
            return;
        }
        self.stop.store(false, Ordering::SeqCst);
        let (voices, stop) = (self.voices.clone(), self.stop.clone());
        self.thread = std::thread::Builder::new()
            .name("audio".into())
            .spawn(move || {
                if let Err(e) = play(voices, stop) {
                    crate::log::error(&format!("sound: {e}"));
                }
            })
            .ok();
    }
}

impl Drop for AudioHub {
    fn drop(&mut self) {
        self.stop_all();
    }
}

/// The playback thread: opens the default output, mixes every playing voice into it until asked to stop.
fn play(voices: Arc<Mutex<Vec<VoiceState>>>, stop: Arc<AtomicBool>) -> Result<(), Box<dyn std::error::Error>> {
    let host = cpal::default_host();
    let device = host.default_output_device().ok_or("no sound output device")?;
    let supported = device.default_output_config()?;
    let format = supported.sample_format();
    let config: cpal::StreamConfig = supported.into();
    let channels = config.channels as usize;
    // the sounds are made at 44.1 kHz; a device at another rate just steps through them faster or slower
    let step = SAMPLE_RATE as f64 / config.sample_rate.0 as f64;
    let mut acc = Vec::<f32>::new();
    let mut mix = move |frames: usize| -> Vec<f32> {
        acc.clear();
        acc.resize(frames * 2, 0.0);
        let mut v = voices.lock().unwrap_or_else(|e| e.into_inner());
        for s in v.iter_mut() {
            mix_into(s, &mut acc, frames, step);
        }
        for x in acc.iter_mut() {
            *x = x.clamp(-1.0, 1.0);
        }
        acc.clone()
    };
    let err = |e| crate::log::error(&format!("sound stream: {e}"));
    let stream = match format {
        cpal::SampleFormat::F32 => device.build_output_stream(
            &config,
            move |data: &mut [f32], _| {
                let m = mix(data.len() / channels);
                for (f, out) in data.chunks_mut(channels).enumerate() {
                    for (c, o) in out.iter_mut().enumerate() {
                        *o = if c < 2 { m[2 * f + c] } else { 0.0 };
                    }
                }
            },
            err,
            None,
        )?,
        cpal::SampleFormat::I16 => device.build_output_stream(
            &config,
            move |data: &mut [i16], _| {
                let m = mix(data.len() / channels);
                for (f, out) in data.chunks_mut(channels).enumerate() {
                    for (c, o) in out.iter_mut().enumerate() {
                        *o = if c < 2 { (m[2 * f + c] * 32000.0) as i16 } else { 0 };
                    }
                }
            },
            err,
            None,
        )?,
        other => return Err(format!("unsupported sample format {other:?}").into()),
    };
    stream.play()?;
    crate::log::debug(&format!("audio started ({} Hz, {channels} channels)", config.sample_rate.0));
    while !stop.load(Ordering::SeqCst) {
        std::thread::sleep(Duration::from_millis(50));
    }
    drop(stream);
    crate::log::debug("audio stopped");
    Ok(())
}

/// Adds one voice to the stereo mix, ramping gain and pan across the buffer so volume changes never click.
/// Equal-power panning, linear interpolation between neighbouring samples (wrapping at the loop seam).
fn mix_into(v: &mut VoiceState, acc: &mut [f32], frames: usize, step: f64) {
    let Some(s) = v.samples.get() else { return };
    if !v.playing || s.is_empty() {
        return;
    }
    let (g0, g1, p0, p1) = (v.applied_gain, v.gain, v.applied_pan, v.pan);
    let step = v.rate as f64 * step;
    for i in 0..frames {
        let t = i as f32 / frames as f32;
        let g = g0 + (g1 - g0) * t;
        let a = ((p0 + (p1 - p0) * t) + 1.0) as f64 * std::f64::consts::PI / 4.0;
        let i0 = v.pos as usize;
        let i1 = if i0 + 1 < s.len() {
            i0 + 1
        } else if v.loops {
            0
        } else {
            i0
        };
        let frac = (v.pos - i0 as f64) as f32;
        let x = (s[i0] + (s[i1] - s[i0]) * frac) * g;
        acc[2 * i] += x * a.cos() as f32;
        acc[2 * i + 1] += x * a.sin() as f32;
        v.pos += step;
        if v.pos >= s.len() as f64 {
            if v.loops {
                v.pos -= s.len() as f64;
            } else {
                v.playing = false;
                break;
            }
        }
    }
    v.applied_gain = g1;
    v.applied_pan = p1;
}

// ---------------------------------------------------------------------- synthesis (`Synth` in Sound.cs)
const RATE: f64 = SAMPLE_RATE as f64;
const TAU: f64 = std::f64::consts::TAU;

fn make_buffer(seconds: f64, fill: impl FnOnce(&mut [f32])) -> Vec<f32> {
    let mut out = vec![0.0f32; (seconds * RATE) as usize];
    fill(&mut out);
    normalize(&mut out);
    out
}

fn normalize(out: &mut [f32]) {
    let peak = out.iter().fold(0.0f32, |p, x| p.max(x.abs()));
    if peak > 0.9 {
        let k = 0.9 / peak;
        for x in out.iter_mut() {
            *x *= k;
        }
    }
}

fn noise(r: &mut NetRandom) -> f64 {
    r.next_double() * 2.0 - 1.0
}

/// Diesel idle-ish rumble. Every frequency is a whole number of cycles per loop, so the loop is seamless.
pub fn plow_engine() -> Vec<f32> {
    make_buffer(2.0, |out| {
        let mut rng = NetRandom::new(42);
        let mut lp = 0.0;
        let harmonics = [(48.0, 1.0), (96.0, 0.5), (144.0, 0.3), (192.0, 0.18), (240.0, 0.1)];
        for (i, o) in out.iter_mut().enumerate() {
            let t = i as f64 / RATE;
            // firing pulses at 24 Hz shape a 48 Hz fundamental with harmonics
            let firing = 0.6 + 0.4 * (TAU * 24.0 * t).sin().max(0.0).powi(3);
            let mut v: f64 = harmonics.iter().map(|(f, a)| a * (TAU * f * t + f).sin()).sum();
            lp += (noise(&mut rng) - lp) * 0.05; // a little rattle: low-passed noise
            v = v * firing + lp * 0.6;
            *o = (v * 0.2) as f32;
        }
    })
}

/// Scraping snow: band-limited noise with a slow grainy texture.
pub fn plow_scrape() -> Vec<f32> {
    make_buffer(2.0, |out| {
        let mut rng = NetRandom::new(7);
        let (mut lp, mut hp, mut prev) = (0.0, 0.0, 0.0);
        for (i, o) in out.iter_mut().enumerate() {
            let t = i as f64 / RATE;
            lp += (noise(&mut rng) - lp) * 0.35; // tame the hiss
            hp = 0.97 * (hp + lp - prev); // remove the rumble
            prev = lp;
            let grain = 0.7 + 0.3 * (TAU * 7.0 * t).sin() * (TAU * 3.0 * t).sin();
            *o = (hp * grain * 0.5) as f32;
        }
        let n = out.len();
        let fade = (0.02 * RATE) as usize;
        for i in 0..fade {
            let k = i as f32 / fade as f32;
            out[i] *= k;
            out[n - 1 - i] *= k;
        }
    })
}

/// Two-tone truck horn: "baa-baaa".
pub fn plow_horn() -> Vec<f32> {
    make_buffer(1.0, |out| {
        let n = out.len();
        let mut honk = |t0: f64, len: f64| {
            let (start, count) = ((t0 * RATE) as usize, (len * RATE) as usize);
            for k in 0..count {
                if start + k >= n {
                    break;
                }
                let t = k as f64 / RATE;
                let env = (t / 0.02).min(1.0) * ((len - t) / 0.05).min(1.0);
                let mut v = 0.0;
                // a slightly sour third, like a real truck horn
                for f in [311.0, 370.0] {
                    for h in 1..=5 {
                        v += (TAU * f * h as f64 * t).sin() / h as f64;
                    }
                }
                out[start + k] += (v * env * 0.12) as f32;
            }
        };
        honk(0.0, 0.22);
        honk(0.32, 0.5);
    })
}

/// A tune for Santa's sleigh: melody as (MIDI note, beats; 0 = rest), one bass root per bar (MIDI). All three are
/// public domain: "Jingle Bells" (James Lord Pierpont, 1857), "Deck the Halls" (Welsh traditional) and "We Wish
/// You a Merry Christmas" (English traditional). Same as on Windows and macOS.
pub struct Tune {
    pub name: &'static str,
    /// Seconds per beat.
    beat: f64,
    beats_per_bar: usize,
    melody: Vec<(i32, f64)>,
    bass_roots: Vec<i32>,
}

pub fn tunes() -> [Tune; 3] {
    [jingle_bells(), deck_the_halls(), we_wish_you()]
}

fn jingle_bells() -> Tune {
    const E5: i32 = 76;
    const F5: i32 = 77;
    const G5: i32 = 79;
    const C5: i32 = 72;
    const D5: i32 = 74;
    #[rustfmt::skip]
    let melody = vec![
        (E5, 1.0), (E5, 1.0), (E5, 2.0), (E5, 1.0), (E5, 1.0), (E5, 2.0), (E5, 1.0), (G5, 1.0), (C5, 1.5), (D5, 0.5), (E5, 4.0),
        (F5, 1.0), (F5, 1.0), (F5, 1.5), (F5, 0.5), (F5, 1.0), (E5, 1.0), (E5, 1.0), (E5, 0.5), (E5, 0.5),
        (E5, 1.0), (D5, 1.0), (D5, 1.0), (E5, 1.0), (D5, 2.0), (G5, 2.0),
        (E5, 1.0), (E5, 1.0), (E5, 2.0), (E5, 1.0), (E5, 1.0), (E5, 2.0), (E5, 1.0), (G5, 1.0), (C5, 1.5), (D5, 0.5), (E5, 4.0),
        (F5, 1.0), (F5, 1.0), (F5, 1.5), (F5, 0.5), (F5, 1.0), (E5, 1.0), (E5, 1.0), (E5, 0.5), (E5, 0.5),
        (G5, 1.0), (G5, 1.0), (F5, 1.0), (D5, 1.0), (C5, 3.0), (0, 1.0),
    ];
    let bass_roots = [C5, C5, C5, C5, F5, C5, D5, G5, C5, C5, C5, C5, F5, C5, G5, C5].map(|r| r - 24).to_vec();
    Tune { name: "jingle-bells", beat: 0.36, beats_per_bar: 4, melody, bass_roots }
}

/// "Deck the Halls", whole verse with its "fa la la" lines, in C.
fn deck_the_halls() -> Tune {
    const B4: i32 = 71;
    const C5: i32 = 72;
    const D5: i32 = 74;
    const E5: i32 = 76;
    const F5: i32 = 77;
    const FS5: i32 = 78;
    const G5: i32 = 79;
    const A5: i32 = 81;
    const B5: i32 = 83;
    const C6: i32 = 84;
    #[rustfmt::skip]
    let line1 = [
        (G5, 1.5), (F5, 0.5), (E5, 1.0), (D5, 1.0), (C5, 1.0), (D5, 1.0), (E5, 1.0), (C5, 1.0),
        (D5, 0.5), (E5, 0.5), (F5, 0.5), (D5, 0.5), (E5, 1.5), (D5, 0.5), (C5, 1.0), (B4, 1.0), (C5, 2.0),
    ];
    #[rustfmt::skip]
    let line3 = [
        (D5, 1.5), (E5, 0.5), (F5, 1.0), (D5, 1.0), (E5, 1.5), (F5, 0.5), (G5, 1.0), (D5, 1.0),
        (E5, 0.5), (FS5, 0.5), (G5, 1.0), (A5, 0.5), (B5, 0.5), (C6, 1.0), (B5, 1.0), (A5, 1.0), (G5, 2.0),
    ];
    #[rustfmt::skip]
    let line4 = [
        (G5, 1.5), (F5, 0.5), (E5, 1.0), (D5, 1.0), (C5, 1.0), (D5, 1.0), (E5, 1.0), (C5, 1.0),
        (A5, 0.5), (A5, 0.5), (A5, 0.5), (A5, 0.5), (G5, 1.5), (F5, 0.5), (E5, 1.0), (D5, 1.0), (C5, 2.0),
    ];
    let melody = [line1, line1, line3, line4].concat();
    const C: i32 = 48;
    const F: i32 = 53;
    const G: i32 = 55;
    const D: i32 = 50;
    Tune {
        name: "deck-the-halls",
        beat: 0.34,
        beats_per_bar: 4,
        melody,
        bass_roots: vec![C, C, G, C, C, C, G, C, G, C, D, G, C, C, F, C],
    }
}

/// "We Wish You a Merry Christmas" in 3/4, in C. The pickup note sits at the end of the loop.
fn we_wish_you() -> Tune {
    const G4: i32 = 67;
    const A4: i32 = 69;
    const B4: i32 = 71;
    const C5: i32 = 72;
    const D5: i32 = 74;
    const E5: i32 = 76;
    const F5: i32 = 77;
    const C: i32 = 48;
    const F: i32 = 53;
    const G: i32 = 55;
    const D: i32 = 50;
    const E: i32 = 52;
    const A: i32 = 45;
    #[rustfmt::skip]
    let tune = Tune {
        name: "we-wish-you",
        beat: 0.4,
        beats_per_bar: 3,
        melody: vec![
            (C5, 1.0), (C5, 0.5), (D5, 0.5), (C5, 0.5), (B4, 0.5), (A4, 1.0), (A4, 1.0), (A4, 1.0),
            (D5, 1.0), (D5, 0.5), (E5, 0.5), (D5, 0.5), (C5, 0.5), (B4, 1.0), (G4, 1.0), (G4, 1.0),
            (E5, 1.0), (E5, 0.5), (F5, 0.5), (E5, 0.5), (D5, 0.5), (C5, 1.0), (A4, 1.0), (G4, 0.5), (G4, 0.5),
            (A4, 1.0), (D5, 1.0), (B4, 1.0), (C5, 2.0), (G4, 1.0), // "year" + the pickup "We" of the next round
        ],
        bass_roots: vec![C, F, D, G, E, A, F, C],
    };
    tune
}

/// One loop of a tune: the melody on a music-box/celesta-like tone, a soft bass and shaken sleigh bells.
pub fn jingle(tune: &Tune) -> Vec<f32> {
    let beat = tune.beat;
    let total_beats: f64 = tune.melody.iter().map(|m| m.1).sum();
    let n = (total_beats * beat * RATE) as usize;
    let mut out = vec![0.0f32; n];
    let freq = |midi: i32| 440.0 * 2f64.powf((midi - 69) as f64 / 12.0);

    // Celesta-like note: a few slightly inharmonic partials with a bright attack and a ringing decay.
    let partials = [(1.0, 1.0, 2.2), (2.0, 0.35, 4.0), (3.01, 0.12, 7.0), (4.17, 0.06, 10.0)];
    let add_bell = |out: &mut [f32], t0: f64, midi: i32, len: f64, amp: f64| {
        let f = freq(midi);
        let dur = (len + 0.6).min(2.5);
        let (start, count) = ((t0 * RATE) as usize, (dur * RATE) as usize);
        for k in 0..count {
            if start + k >= n {
                break;
            }
            let t = k as f64 / RATE;
            let v: f64 = partials.iter().map(|(m, a, d)| a * (-t * d).exp() * (TAU * f * m * t).sin()).sum();
            out[start + k] += (v * amp * (t / 0.004).min(1.0)) as f32;
        }
    };
    // Soft round bass note.
    let add_bass = |out: &mut [f32], t0: f64, midi: i32, len: f64| {
        let f = freq(midi);
        let (start, count) = ((t0 * RATE) as usize, (len * RATE) as usize);
        for k in 0..count {
            if start + k >= n {
                break;
            }
            let t = k as f64 / RATE;
            let env = (t / 0.01).min(1.0) * (-t * 3.0).exp();
            out[start + k] += (0.16 * env * ((TAU * f * t).sin() + 0.3 * (2.0 * TAU * f * t).sin())) as f32;
        }
    };
    // One sleigh bell: a short, bright cluster of inharmonic partials plus a little noise.
    let mut rng = NetRandom::new(1857);
    let bell_partials = [1.0, 1.47, 2.09, 2.56, 3.18];
    let add_jingle = |out: &mut [f32], rng: &mut NetRandom, t0: f64, amp: f64| {
        let b = 2300.0 + rng.next_double() * 500.0;
        let (start, count) = ((t0 * RATE) as i64, (0.09 * RATE) as i64);
        for k in 0..count {
            let idx = start + k;
            if idx >= n as i64 || idx < 0 {
                break;
            }
            let t = k as f64 / RATE;
            let mut v: f64 = bell_partials
                .iter()
                .enumerate()
                .map(|(j, p)| (TAU * b * p * t + j as f64).sin() / (j + 2) as f64)
                .sum();
            v += noise(rng) * 0.35 * (-t * 120.0).exp();
            out[idx as usize] += (v * (-t * 55.0).exp() * amp) as f32;
        }
    };

    let mut time = 0.0;
    for &(note, beats) in &tune.melody {
        if note > 0 {
            add_bell(&mut out, time, note, beats * beat, 0.22);
        }
        time += beats * beat;
    }
    // bass: the root on the first beat of each bar and the fifth on the third
    let bpb = tune.beats_per_bar;
    let bars = (total_beats / bpb as f64) as usize;
    for b in 0..bars {
        let root = tune.bass_roots[b % tune.bass_roots.len()];
        let t0 = (b * bpb) as f64;
        add_bass(&mut out, t0 * beat, root, beat * 1.8);
        add_bass(&mut out, (t0 + 2.0) * beat, root + 7, beat * (bpb as f64 - 2.0 + 0.8));
    }
    // sleigh bells: a shake on every eighth note, accented on the beat, each shake a few bells
    let mut e = 0;
    while e as f64 * 0.5 < total_beats {
        let tb = e as f64 * 0.5 * beat;
        let accent = if e % 2 == 0 { 1.0 } else { 0.6 };
        for j in 0..4 {
            let jitter = rng.next_double() * 0.006;
            add_jingle(&mut out, &mut rng, tb + j as f64 * 0.012 + jitter, 0.05 * accent);
        }
        e += 1;
    }

    normalize(&mut out); // gentle limiter so overlapping notes never clip
    let fade = (0.01 * RATE) as usize;
    for i in 0..fade {
        let k = i as f32 / fade as f32;
        out[i] *= k;
        out[n - 1 - i] *= k;
    }
    out
}

/// The leaf collector's suction (autumn's form of the scraping): a rush of air through a wide hose, i.e. noise
/// shaped by a broad resonance and a hollow one from the hose, over the fan's steady whine.
pub fn leaf_suction() -> Vec<f32> {
    const LEN: f64 = 3.0;
    make_buffer(LEN, |out| {
        let mut rng = NetRandom::new(77);
        let n = out.len();
        let over = (0.3 * RATE) as usize;
        let mut air = vec![0.0f32; n + over];
        // two resonators (state-variable band-passes): the rush around 900 Hz and the hose around 260 Hz
        let (mut low_a, mut band_a, mut low_b, mut band_b) = (0.0f64, 0.0f64, 0.0f64, 0.0f64);
        let pi = std::f64::consts::PI;
        let (f_a, f_b) = (2.0 * (pi * 900.0 / RATE).sin(), 2.0 * (pi * 260.0 / RATE).sin());
        for (i, a) in air.iter_mut().enumerate() {
            let t = i as f64 / RATE;
            let white = noise(&mut rng);
            let high_a = white - low_a - 1.4 * band_a;
            band_a += f_a * high_a;
            low_a += f_a * band_a;
            let high_b = white - low_b - 0.5 * band_b;
            band_b += f_b * high_b;
            low_b += f_b * band_b;
            // the air flutters a little as leaves pass through (whole cycles per loop)
            let w = TAU * t / LEN;
            let flutter = 0.85 + 0.15 * (w * 4.0).sin() * (w * 11.0 + 0.7).sin();
            *a = ((band_a * 0.55 + band_b * 0.12) * flutter) as f32;
        }
        // made a little longer than the loop and cross-faded into its own start, so the loop has no seam
        for i in 0..over {
            let k = i as f32 / over as f32;
            air[i] = air[i] * k + air[n + i] * (1.0 - k);
        }
        for (i, o) in out.iter_mut().enumerate() {
            let t = i as f64 / RATE;
            // the fan: a whine with a slow beat between two close tones (all whole cycles per loop)
            let whine = 0.05 * (TAU * 520.0 * t).sin()
                + 0.035 * (TAU * 524.0 * t).sin()
                + 0.02 * (TAU * 1040.0 * t).sin()
                + 0.012 * (TAU * 1563.0 * t).sin();
            *o = air[i] * 0.8 + (whine * 1.6) as f32;
        }
    })
}

// ---------------------------------------------------------------------- the donkey cart (the Day of the Dead's plow)
/// The leg phases at which the drawn donkey's hooves land, as shares of a step cycle, with how loud each is and its
/// pitch: the near legs (phases 0 and pi in the drawing, `layer/muertos.rs`) louder than the far ones (1.2 and
/// 1.2 + pi).
const HOOF_FALLS: [(f64, f64, f64); 4] =
    [(0.0, 1.0, 1.0), (1.2 / TAU, 0.7, 0.86), (0.5, 0.95, 1.07), (0.5 + 1.2 / TAU, 0.65, 0.9)];

/// Adds `make(k)` (k = samples since the start) at `start`, wrapping round the end of the loop.
fn add_wrapped(out: &mut [f32], start: i64, count: usize, mut make: impl FnMut(usize) -> f64) {
    let n = out.len() as i64;
    if n == 0 {
        return;
    }
    for k in 0..count {
        let at = (start + k as i64).rem_euclid(n) as usize;
        out[at] += make(k) as f32;
    }
}

/// The donkey cart rolling: four hooves per step cycle (`cycle` seconds, `figures::donkey_step_cycle`) and the
/// wooden wheel creaking once a turn, over the low rumble of the wheel. The loop is 8 step cycles, which is exactly
/// 5 turns of the wheel (the legs swing 1.6 times per turn of it), so both repeat seamlessly.
pub fn donkey_cart(cycle: f64) -> Vec<f32> {
    let cycle = cycle.clamp(0.2, 2.0);
    let len = 8.0 * cycle;
    make_buffer(len, |out| {
        let mut rng = NetRandom::new(1102);
        let n = out.len();
        // hooves: a short hollow "tok" (two inharmonic modes of the hoof and the ground) with a soft thump and a
        // click of grit, each a little different
        for c in 0..8 {
            for (at, fall_loud, pitch) in HOOF_FALLS {
                let t0 = (c as f64 + at) * cycle + (rng.next_double() - 0.5) * 0.012;
                let f1 = (760.0 + rng.next_double() * 160.0) * pitch;
                let f2 = f1 * 2.37;
                let loud = fall_loud * (0.8 + 0.25 * rng.next_double());
                add_wrapped(out, (t0 * RATE) as i64, (0.12 * RATE) as usize, |k| {
                    let t = k as f64 / RATE;
                    let tok = 0.55 * (TAU * f1 * t).sin() * (-t / 0.016).exp()
                        + 0.22 * (TAU * f2 * t).sin() * (-t / 0.008).exp();
                    let thump = 0.5 * (TAU * 120.0 * t).sin() * (-t / 0.035).exp();
                    let grit = noise(&mut rng) * 0.35 * (-t / 0.003).exp();
                    loud * (tok + thump + grit) * 0.55
                });
            }
        }
        // the wheel creaks once a turn: stick-slip pulses, getting quicker, ringing a wooden resonance
        let turn = len / 5.0;
        for w in 0..5 {
            let t0 = w as f64 * turn + turn * 0.35 + (rng.next_double() - 0.5) * 0.04;
            let dur = 0.2 + rng.next_double() * 0.08;
            let f0 = 150.0 + rng.next_double() * 40.0;
            let rise = 1.5 + rng.next_double() * 0.3;
            let res = 1250.0 + rng.next_double() * 300.0;
            let rr = 0.9965;
            let cw = 2.0 * rr * (TAU * res / RATE).cos();
            let (mut y1, mut y2, mut phase) = (0.0f64, 0.0f64, 0.0f64);
            add_wrapped(out, (t0 * RATE) as i64, ((dur + 0.06) * RATE) as usize, |k| {
                let t = k as f64 / RATE;
                let mut x = 0.0;
                if t < dur {
                    phase += f0 * (1.0 + (rise - 1.0) * t / dur) / RATE;
                    if phase >= 1.0 {
                        phase -= 1.0;
                        x = 1.0;
                    }
                }
                let y = cw * y1 - rr * rr * y2 + x;
                y2 = y1;
                y1 = y;
                let env = if t < dur { (std::f64::consts::PI * (t / dur).min(1.0)).sin() } else { 1.0 };
                y * env * 0.012
            });
        }
        // the rumble of the wheel on the ground: low-passed noise, cross-faded over the loop's seam
        let over = (0.2 * RATE) as usize;
        let (mut lp, mut lp2) = (0.0f64, 0.0f64);
        let mut rumble = vec![0.0f64; n + over];
        for r in rumble.iter_mut() {
            lp += (noise(&mut rng) - lp) * 0.02;
            lp2 += (lp - lp2) * 0.05;
            *r = lp2;
        }
        for i in 0..over {
            let k = i as f64 / over as f64;
            rumble[i] = rumble[i] * k + rumble[n + i] * (1.0 - k);
        }
        for (o, r) in out.iter_mut().zip(&rumble) {
            *o += (*r * 0.2) as f32;
        }
    })
}

/// The calaca's broom: a swish on each forward stroke (the broom swings twice per step cycle), with a rustle of
/// petals. Same loop length as `donkey_cart`, so the two keep the same pace.
pub fn broom_sweep(cycle: f64) -> Vec<f32> {
    let cycle = cycle.clamp(0.2, 2.0);
    make_buffer(8.0 * cycle, |out| {
        let mut rng = NetRandom::new(2011);
        let pi = std::f64::consts::PI;
        for s in 0..16 {
            let t0 = (s as f64 * 0.5 + 0.12) * cycle + (rng.next_double() - 0.5) * 0.01;
            let dur = cycle * 0.3;
            let loud = 0.8 + 0.3 * rng.next_double();
            // band-passed noise whose centre falls as the bristles slow down
            let (mut low, mut band) = (0.0f64, 0.0f64);
            add_wrapped(out, (t0 * RATE) as i64, (dur * RATE) as usize, |k| {
                let t = k as f64 / RATE;
                let u = t / dur;
                let fc = 3200.0 - 1700.0 * u;
                let f = 2.0 * (pi * fc / RATE).sin();
                let high = noise(&mut rng) - low - 0.9 * band;
                band += f * high;
                low += f * band;
                let env = (pi * u).sin().powi(2) * (1.0 - 0.4 * u);
                // petals: a few tiny ticks in the swish
                let tick = if rng.next_double() < 0.0015 { (rng.next_double() - 0.5) * 1.2 } else { 0.0 };
                (band * 0.5 + tick) * env * loud
            });
        }
    })
}

/// The donkey's bray (the cart's form of the horn): "hee-haw, hee-haw". The "hee" is drawn in, high and thin; the
/// "haw" pushed out, low, loud and rough. A buzzy source (harmonics up to 5 kHz) through two formant resonances
/// for each vowel.
pub fn donkey_bray() -> Vec<f32> {
    make_buffer(1.9, |out| {
        let mut rng = NetRandom::new(315);
        let n = out.len();
        let pi = std::f64::consts::PI;
        // start, length, f0 from, f0 to, formant 1, formant 2, loudness, roughness
        let parts: [[f64; 8]; 4] = [
            [0.00, 0.30, 470.0, 560.0, 1150.0, 2700.0, 0.45, 0.10],
            [0.34, 0.42, 210.0, 150.0, 720.0, 1150.0, 1.00, 0.35],
            [0.84, 0.26, 450.0, 530.0, 1150.0, 2700.0, 0.40, 0.10],
            [1.14, 0.48, 200.0, 135.0, 700.0, 1100.0, 0.95, 0.40],
        ];
        for p in parts {
            let (start, count) = ((p[0] * RATE) as usize, (p[1] * RATE) as usize);
            let length = p[1];
            let (mut phase, mut l1, mut b1, mut l2, mut b2, mut jitter) = (0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64);
            let (g1, g2) = (2.0 * (pi * p[4] / RATE).sin(), 2.0 * (pi * p[5] / RATE).sin());
            for k in 0..count {
                if start + k >= n {
                    break;
                }
                let t = k as f64 / RATE;
                let u = t / length;
                // the pitch rises (hee) or falls (haw) along a curve, with a little wobble
                jitter += (noise(&mut rng) - jitter) * 0.002;
                let glide = p[2] + (p[3] - p[2]) * (pi / 2.0 * u).sin();
                let f0 = glide * (1.0 + 0.025 * (TAU * 6.0 * t).sin() + 0.05 * jitter);
                phase += f0 / RATE;
                if phase >= 1.0 {
                    phase -= 1.0;
                }
                let mut src = 0.0f64;
                let harmonics = ((5000.0 / f0) as i32).max(1);
                for h in 1..=harmonics {
                    src += (TAU * h as f64 * phase).sin() / h as f64;
                }
                // roughness: the voice flutters at about 28 Hz
                let flutter = 0.5 + 0.5 * (TAU * 28.0 * t).sin();
                src *= 1.0 - p[7] * flutter;
                let h1 = src - l1 - 0.25 * b1;
                b1 += g1 * h1;
                l1 += g1 * b1;
                let h2 = src - l2 - 0.3 * b2;
                b2 += g2 * h2;
                l2 += g2 * b2;
                let env = (t / 0.03).min(1.0) * ((length - t) / 0.06).min(1.0);
                let voice = b1 * 0.6 + b2 * 0.35 + src * 0.05;
                out[start + k] += (voice * env * p[6] * 0.3) as f32;
            }
        }
    })
}

// ---------------------------------------------------------------------- halloween
/// The witch's tune: an original slow waltz in A minor (8 bars of 3/4, about 10 s, looping), sung by a thin
/// wavering voice that slides from note to note (like a theremin) over a low organ holding the bar's root and
/// fifth. Written for JuleHygge, so it is free of rights. Same as `Synth.WitchTune` in `src/Sound.cs`.
pub fn witch_tune() -> Vec<f32> {
    const BEAT: f64 = 0.42;
    const E4: i32 = 64;
    const GS4: i32 = 68;
    const A4: i32 = 69;
    const B4: i32 = 71;
    const C5: i32 = 72;
    const D5: i32 = 74;
    const E5: i32 = 76;
    #[rustfmt::skip]
    let melody: [(i32, f64); 14] = [
        (E5, 2.0), (C5, 1.0),   (D5, 2.0), (B4, 1.0),    (C5, 1.0), (B4, 1.0), (A4, 1.0),   (E4, 3.0),
        (A4, 2.0), (C5, 1.0),   (B4, 2.0), (GS4, 1.0),   (A4, 3.0),                         (0, 3.0),
    ];
    let roots: [i32; 8] = [45, 40, 45, 40, 41, 40, 45, 45];
    fn freq(midi: i32) -> f64 {
        440.0 * 2f64.powf((midi - 69) as f64 / 12.0)
    }
    let beats: f64 = melody.iter().map(|m| m.1).sum();
    let total = beats * BEAT;
    make_buffer(total, |out| {
        let n = out.len();
        let pi = std::f64::consts::PI;
        // the voice: the pitch glides toward each note, with a slow vibrato that deepens as the note is held
        let (mut phase, mut pitch, mut level) = (0.0f64, freq(melody[0].0), 0.0f64);
        let (mut note_start, mut note_end, mut idx) = (0.0f64, melody[0].1 * BEAT, 0usize);
        for (i, o) in out.iter_mut().enumerate() {
            let t = i as f64 / RATE;
            while t >= note_end && idx < melody.len() - 1 {
                idx += 1;
                note_start = note_end;
                note_end += melody[idx].1 * BEAT;
            }
            let note = melody[idx].0;
            let (held, left) = (t - note_start, note_end - t);
            if note > 0 {
                pitch += (freq(note) - pitch) * 0.0009;
            }
            let want = if note > 0 { (held / 0.06).min(1.0) * (left / 0.09).min(1.0) } else { 0.0 };
            level += (want - level) * 0.002;
            let vibrato = 1.0 + 0.008 * (held / 0.35).min(1.0) * (TAU * 5.6 * t).sin();
            phase += pitch * vibrato / RATE;
            if phase >= 1.0 {
                phase -= 1.0;
            }
            let voice = (TAU * phase).sin() + 0.16 * (2.0 * TAU * phase).sin() + 0.05 * (6.0 * pi * phase).sin();
            *o += (voice * level * 0.34) as f32;
        }
        // the organ: root and fifth per bar, soft, swelling in and out so the loop has no click
        let stops: [(f64, f64); 5] = [(1.0, 1.0), (1.5, 0.55), (2.0, 0.4), (3.0, 0.18), (4.0, 0.1)];
        for (b, root) in roots.iter().enumerate() {
            let (start, count) = (((b * 3) as f64 * BEAT * RATE) as usize, (3.0 * BEAT * RATE) as usize);
            let f = freq(*root);
            for k in 0..count {
                if start + k >= n {
                    break;
                }
                let (t, u) = (k as f64 / RATE, k as f64 / count as f64);
                let env = (u / 0.12).min(1.0) * ((1.0 - u) / 0.12).min(1.0);
                let v: f64 = stops.iter().map(|(mult, amp)| amp * (TAU * f * mult * t).sin()).sum();
                out[start + k] += (v * env * 0.1) as f32;
            }
        }
    })
}

/// The wind Halloween's ghosts blow the leaves away with: a hollow rush of air that rises and falls, and under it
/// two wavering "oooo" voices a third apart. A 4 s loop: every tone and every swell is a whole number of cycles in
/// it, and the air is made a little longer and faded into its own start, so there is no seam.
pub fn ghost_wind() -> Vec<f32> {
    const LEN: f64 = 4.0;
    make_buffer(LEN, |out| {
        let mut rng = NetRandom::new(3110);
        let n = out.len();
        let pi = std::f64::consts::PI;
        let over = (0.3 * RATE) as usize;
        let mut air = vec![0.0f64; n + over];
        let (mut low, mut band) = (0.0f64, 0.0f64);
        for (i, a) in air.iter_mut().enumerate() {
            let t = i as f64 / RATE;
            // a resonance that slides up and down between about 350 and 900 Hz
            let fc = 620.0 + 280.0 * (TAU * 0.5 * t).sin();
            let f = 2.0 * (pi * fc / RATE).sin();
            let high = noise(&mut rng) - low - 0.35 * band;
            band += f * high;
            low += f * band;
            *a = band * (0.6 + 0.4 * (TAU * 0.25 * t).sin());
        }
        for i in 0..over {
            let k = i as f64 / over as f64;
            air[i] = air[i] * k + air[n + i] * (1.0 - k);
        }
        for (i, o) in out.iter_mut().enumerate() {
            let t = i as f64 / RATE;
            let swell = 0.5 + 0.5 * (TAU * 0.25 * t - 1.0).sin();
            let vib = 1.0 + 0.012 * (TAU * 5.0 * t).sin();
            let voices = (TAU * 330.0 * vib * t).sin()
                + 0.8 * (TAU * 392.0 * vib * t + 1.0).sin()
                + 0.25 * (TAU * 660.0 * vib * t).sin();
            *o = (air[i] * 0.22 + voices * swell * 0.035) as f32;
        }
    })
}

// ---------------------------------------------------------------------- de dødes dag
/// The butterflies' tune: an original little waltz in D minor (16 bars of 3/4, about 18 s, looping) in the style
/// of a Mexican son: the melody on a marimba (long notes rolled, as marimba players do) over a guitar that plays
/// the bass on the first beat and strums the chord on the second and third (down, up, down). Written for
/// JuleHygge, so it is free of rights. Same as `Synth.MuertosSon` in `src/Sound.cs`.
pub fn muertos_son() -> Vec<f32> {
    const BEAT: f64 = 0.38;
    const A4: i32 = 69;
    const CS5: i32 = 73;
    const C5: i32 = 72;
    const D5: i32 = 74;
    const E5: i32 = 76;
    const F5: i32 = 77;
    const G5: i32 = 79;
    const A5: i32 = 81;
    const BB5: i32 = 82;
    const C6: i32 = 84;
    const D6: i32 = 86;
    #[rustfmt::skip]
    let melody: [(i32, f64); 47] = [
        (A4, 1.0), (D5, 1.0), (F5, 1.0),               (A5, 2.0), (G5, 0.5), (F5, 0.5),
        (E5, 1.5), (F5, 0.5), (G5, 1.0),               (A5, 2.0), (0, 1.0),
        (F5, 1.0), (E5, 0.5), (D5, 0.5), (F5, 1.0),    (A5, 1.0), (D6, 1.0), (A5, 1.0),
        (BB5, 1.0), (A5, 0.5), (G5, 0.5), (F5, 1.0),   (E5, 2.0), (0, 1.0),
        (C5, 1.0), (F5, 1.0), (A5, 1.0),               (C6, 2.0), (A5, 1.0),
        (BB5, 1.0), (G5, 1.0), (E5, 1.0),              (E5, 1.0), (G5, 1.0), (BB5, 1.0),
        (A5, 1.5), (G5, 0.5), (F5, 1.0),               (F5, 1.0), (E5, 0.5), (D5, 0.5), (A5, 1.0),
        (G5, 1.0), (E5, 1.0), (CS5, 1.0),              (D5, 2.0), (0, 1.0),
    ];
    // the guitar's chords, lowest string first (the first note is the bass)
    let dm: &[i32] = &[50, 57, 62, 65];
    let a7: &[i32] = &[45, 52, 55, 61, 64];
    let gm: &[i32] = &[43, 50, 55, 58, 62];
    let fmaj: &[i32] = &[41, 48, 53, 57, 60];
    let c7: &[i32] = &[48, 52, 58, 60, 64];
    let chords: [&[i32]; 16] = [dm, dm, a7, a7, dm, dm, gm, a7, fmaj, fmaj, c7, c7, gm, dm, a7, dm];
    let total_beats: f64 = melody.iter().map(|m| m.1).sum();
    let n = (total_beats * BEAT * RATE) as usize;
    let mut out = vec![0.0f32; n];
    let mut rng = NetRandom::new(1102);

    fn freq(midi: i32) -> f64 {
        440.0 * 2f64.powf((midi - 69) as f64 / 12.0)
    }
    /// One marimba stroke: the bar's fundamental with its 4th and 10th partials (a marimba bar is tuned so), all
    /// dying fast, plus a soft knock of the mallet. Wraps round the loop's end, so the seam is clean.
    fn strike(out: &mut [f32], t0: f64, midi: i32, amp: f64) {
        let n = out.len();
        let f = freq(midi);
        let (start, count) = ((t0 * RATE) as usize, (1.2 * RATE) as usize);
        for k in 0..count {
            let t = k as f64 / RATE;
            let env = (t / 0.002).min(1.0);
            let mut v = (-t * 4.5).exp() * (TAU * f * t).sin();
            v += 0.22 * (-t * 14.0).exp() * (TAU * f * 4.0 * t).sin();
            v += 0.05 * (-t * 30.0).exp() * (TAU * f * 10.0 * t).sin();
            v += 0.15 * (-t * 300.0).exp() * (TAU * 180.0 * t).sin();
            out[(start + k) % n] += (v * env * amp) as f32;
        }
    }
    /// One plucked string (Karplus-Strong): a burst of soft noise circulating in a delay line one period long,
    /// averaged a little each round, so it rings and darkens like a nylon string.
    fn pluck(out: &mut [f32], rng: &mut NetRandom, t0: f64, midi: i32, amp: f64, len: f64) {
        let n = out.len();
        let period = ((RATE / freq(midi)) as usize).max(2);
        let mut line = vec![0.0f64; period];
        let mut prev = 0.0f64;
        for l in line.iter_mut() {
            prev = prev * 0.5 + noise(rng) * 0.5;
            *l = prev;
        }
        let (start, count) = ((t0 * RATE) as usize, (len * RATE) as usize);
        for k in 0..count {
            let (j, j2) = (k % period, (k + 1) % period);
            let v = line[j];
            line[j] = 0.4985 * (line[j] + line[j2]);
            let fade_out = if k + 800 > count { (count - k) as f64 / 800.0 } else { 1.0 };
            out[(start + k) % n] += (v * amp * fade_out) as f32;
        }
    }
    /// Down: every string but the bass, lowest first. Up: the three highest, highest first.
    fn strum(out: &mut [f32], rng: &mut NetRandom, t0: f64, chord: &[i32], down: bool, amp: f64) {
        let count = if down { chord.len() - 1 } else { 3 };
        for k in 0..count {
            let midi = if down { chord[1 + k] } else { chord[chord.len() - 1 - k] };
            pluck(out, rng, t0 + k as f64 * 0.011, midi, amp, BEAT * 1.4);
        }
    }

    // melody: short notes struck once, long ones rolled
    let mut at = 0.0f64;
    for (note, len) in melody {
        if note > 0 {
            if len >= 1.5 {
                let mut r = 0.0f64;
                while r < len * BEAT - 0.1 {
                    strike(&mut out, at + r, note, if r == 0.0 { 0.30 } else { 0.17 });
                    r += 0.085;
                }
            } else {
                strike(&mut out, at, note, 0.30);
            }
        }
        at += len * BEAT;
    }
    // guitar: bass on 1, strum down on 2, up on the "and", down on 3
    for (b, chord) in chords.iter().enumerate() {
        let t0 = (b * 3) as f64 * BEAT;
        pluck(&mut out, &mut rng, t0, chord[0], 0.38, BEAT * 2.2);
        strum(&mut out, &mut rng, t0 + BEAT, chord, true, 0.16);
        strum(&mut out, &mut rng, t0 + BEAT * 1.5, chord, false, 0.10);
        strum(&mut out, &mut rng, t0 + BEAT * 2.0, chord, true, 0.14);
    }
    normalize(&mut out);
    out
}

// ---------------------------------------------------------------------- geese (autumn's flyer)
/// The two moods of a flock of geese passing over; each trip picks one (alone twice as often as in wind).
pub const GOOSE_MOODS: [&str; 2] = ["alene", "blaest"];

/// The flock itself is a recording (`assets/lyd/gaes-flok.wav`, see `KILDER.md` there): synthesized calls sounded
/// far too artificial. It is compiled into the binary, as it is a resource in the Windows exe.
static GOOSE_WAV: &[u8] = include_bytes!("../../assets/lyd/gaes-flok.wav");

/// The recording mixed to mono at the synth's sample rate, peak 0.6. None if it is not 16-bit PCM.
fn goose_recording() -> Option<&'static [f32]> {
    static REC: OnceLock<Option<Vec<f32>>> = OnceLock::new();
    REC.get_or_init(|| decode_wav(GOOSE_WAV)).as_deref()
}

fn decode_wav(d: &[u8]) -> Option<Vec<f32>> {
    let u16_at = |p: usize| d.get(p..p + 2).map(|b| u16::from_le_bytes([b[0], b[1]]));
    let u32_at = |p: usize| d.get(p..p + 4).map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]));
    // find the format and the samples
    let (mut channels, mut rate, mut bits) = (0usize, 0u32, 0u16);
    let mut data: Option<&[u8]> = None;
    let mut pos = 12;
    while pos + 8 <= d.len() {
        let size = u32_at(pos + 4)? as usize;
        match &d[pos..pos + 4] {
            b"fmt " => {
                channels = u16_at(pos + 10)? as usize;
                rate = u32_at(pos + 12)?;
                bits = u16_at(pos + 22)?;
            }
            b"data" => {
                let start = pos + 8;
                data = Some(&d[start..start.saturating_add(size).min(d.len())]);
                break;
            }
            _ => {}
        }
        pos += 8 + size + (size & 1);
    }
    let data = data?;
    if bits != 16 || channels < 1 || rate < 8000 {
        return None;
    }
    let mono: Vec<f32> = data
        .chunks_exact(2 * channels)
        .map(|frame| {
            let sum: i32 = frame.chunks_exact(2).map(|b| i16::from_le_bytes([b[0], b[1]]) as i32).sum();
            sum as f32 / channels as f32 / 32768.0
        })
        .collect();
    let m = mono.len();
    if m < 2 {
        return None;
    }
    let ratio = rate as f64 / RATE;
    let out_n = ((m - 1) as f64 / ratio) as usize;
    let mut rec = Vec::with_capacity(out_n);
    let mut peak = 0.0f32;
    for i in 0..out_n {
        let p = i as f64 * ratio;
        let j = (p as usize).min(m - 2);
        let f = (p - j as f64) as f32;
        let v = mono[j] * (1.0 - f) + mono[j + 1] * f;
        peak = peak.max(v.abs());
        rec.push(v);
    }
    if peak > 0.0 {
        let k = 0.6 / peak;
        for v in &mut rec {
            *v *= k;
        }
    }
    Some(rec)
}

/// One seamless loop of geese calling, as long as the recording: 0 = the flock alone, 1 = farther off (quieter and
/// duller) over synthesized gusts of wind. A second of silence without the recording.
pub fn geese(mood: usize) -> Vec<f32> {
    let over = (0.5 * RATE) as usize;
    let Some(rec) = goose_recording().filter(|r| r.len() > over * 4) else {
        return vec![0.0; RATE as usize];
    };
    let n = rec.len() - over;
    let len = n as f64 / RATE;
    let mut out = vec![0.0f32; n];

    // The recording, its tail cross-faded into its start so the loop has no seam; a far flock is quieter and has
    // lost its brightness (a one-pole low-pass).
    let (level, open) = if mood == 0 { (1.0f32, 1.0f32) } else { (0.6, 0.35) };
    let mut smooth = 0.0f32;
    for (i, o) in out.iter_mut().enumerate() {
        let mut s = rec[i];
        if i < over {
            let k = i as f32 / over as f32;
            s = s * k + rec[n + i] * (1.0 - k);
        }
        smooth += (s - smooth) * open;
        *o = smooth * level;
    }
    if mood > 0 {
        // The wind under the calls: made a little longer than the loop and cross-faded into its own start, so the
        // loop has no seam.
        let mut rng = NetRandom::new(1200 + mood as i32);
        let mut bed = vec![0.0f32; n + over];
        let (mut lp1, mut lp2) = (0.0f64, 0.0f64);
        for (i, b) in bed.iter_mut().enumerate() {
            let tt = i as f64 / RATE;
            // gusts: the wind grows louder and brighter together (whole cycles per loop)
            let w = TAU * tt / len;
            let gq = 0.5 + 0.5 * (0.6 * (w * 2.0).sin() + 0.4 * (w * 5.0 + 1.3).sin());
            let gust = gq * gq;
            let a = 0.012 + 0.05 * gust;
            lp1 += (noise(&mut rng) - lp1) * a;
            lp2 += (lp1 - lp2) * a;
            *b = (lp2 * (0.25 + 0.75 * gust) * 1.9) as f32;
        }
        for i in 0..over {
            let k = i as f32 / over as f32;
            bed[i] = bed[i] * k + bed[n + i] * (1.0 - k);
        }
        for (o, b) in out.iter_mut().zip(&bed) {
            *o += b;
        }
    }
    normalize(&mut out);
    out
}

/// `--sound-test=DIR` (`--lyd-test=DIR`): writes each sound as a 16-bit mono WAV file plus a summary, with the same
/// names as `--lyd-test` on Windows, so they can be listened to and compared.
pub fn write_test_files(dir: &std::path::Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)?;
    let mut sounds: Vec<(String, Vec<f32>)> =
        tunes().iter().map(|t| (format!("julemand-{}", t.name), jingle(t))).collect();
    sounds.push(("sneplov-motor".into(), plow_engine()));
    sounds.push(("sneplov-skraben".into(), plow_scrape()));
    sounds.push(("sneplov-horn".into(), plow_horn()));
    sounds.push(("loevsuger-sug".into(), leaf_suction()));
    let cycle = crate::figures::donkey_step_cycle();
    sounds.push(("sommerfugle-son".into(), muertos_son()));
    sounds.push(("aeselkaerre-rul".into(), donkey_cart(cycle)));
    sounds.push(("aeselkaerre-kost".into(), broom_sweep(cycle)));
    sounds.push(("aeselkaerre-broel".into(), donkey_bray()));
    sounds.push(("heks-melodi".into(), witch_tune()));
    sounds.push(("spoegelser-sus".into(), ghost_wind()));
    for (mood, name) in GOOSE_MOODS.iter().enumerate() {
        sounds.push((format!("gaes-{name}"), geese(mood)));
    }
    let mut summary = String::new();
    for (name, s) in &sounds {
        let mut wav = Vec::with_capacity(44 + s.len() * 2);
        let data_len = (s.len() * 2) as u32;
        wav.extend_from_slice(b"RIFF");
        wav.extend_from_slice(&(36 + data_len).to_le_bytes());
        wav.extend_from_slice(b"WAVEfmt ");
        wav.extend_from_slice(&16u32.to_le_bytes());
        wav.extend_from_slice(&1u16.to_le_bytes()); // PCM
        wav.extend_from_slice(&1u16.to_le_bytes()); // mono
        wav.extend_from_slice(&SAMPLE_RATE.to_le_bytes());
        wav.extend_from_slice(&(SAMPLE_RATE * 2).to_le_bytes());
        wav.extend_from_slice(&2u16.to_le_bytes());
        wav.extend_from_slice(&16u16.to_le_bytes());
        wav.extend_from_slice(b"data");
        wav.extend_from_slice(&data_len.to_le_bytes());
        for x in s {
            wav.extend_from_slice(&((x.clamp(-1.0, 1.0) * 32000.0) as i16).to_le_bytes());
        }
        std::fs::write(dir.join(format!("{name}.wav")), wav)?;
        let peak = s.iter().fold(0.0f64, |p, x| p.max(x.abs() as f64));
        let rms = (s.iter().map(|x| (*x as f64) * (*x as f64)).sum::<f64>() / s.len() as f64).sqrt();
        summary.push_str(&format!("{name}: {:.1} s  peak {peak:.2}  rms {rms:.3}\r\n", s.len() as f64 / RATE));
    }
    std::fs::write(dir.join("summary.txt"), summary)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sounds_are_sane_and_loop_lengths_match_the_tunes() {
        for t in tunes() {
            let s = jingle(&t);
            let beats: f64 = t.melody.iter().map(|m| m.1).sum();
            assert_eq!(s.len(), (beats * t.beat * RATE) as usize, "{}", t.name);
            // whole bars, so the loop keeps the beat
            assert_eq!(beats % t.beats_per_bar as f64, 0.0, "{}", t.name);
            let peak = s.iter().fold(0.0f32, |p, x| p.max(x.abs()));
            assert!(peak > 0.2 && peak <= 0.9001, "{} peak {peak}", t.name);
        }
        for s in [plow_engine(), plow_scrape(), plow_horn(), leaf_suction()] {
            assert!(s.iter().all(|x| x.is_finite() && x.abs() <= 0.9001));
        }
    }

    #[test]
    fn the_day_of_the_dead_sounds_are_sane_and_keep_the_donkeys_pace() {
        let cycle = crate::figures::donkey_step_cycle();
        // (the hooves land about 1.7 times a second per leg)
        assert!(cycle > 0.4 && cycle < 0.8, "cycle {cycle}");
        let (cart, broom) = (donkey_cart(cycle), broom_sweep(cycle));
        assert_eq!(cart.len(), broom.len());
        assert_eq!(cart.len(), (8.0 * cycle * RATE) as usize);
        let son = muertos_son();
        // 16 bars of 3/4 at 0.38 s a beat
        assert_eq!(son.len(), (48.0 * 0.38 * RATE) as usize);
        for (name, s) in [("cart", cart), ("broom", broom), ("bray", donkey_bray()), ("son", son)] {
            let peak = s.iter().fold(0.0f32, |p, x| p.max(x.abs()));
            assert!(peak > 0.1 && peak <= 0.9001 && s.iter().all(|x| x.is_finite()), "{name} peak {peak}");
        }
    }

    #[test]
    fn halloweens_sounds_are_sane() {
        let tune = witch_tune();
        // 8 bars of 3/4 at 0.42 s a beat
        assert!((tune.len() as i64 - (24.0 * 0.42 * RATE) as i64).abs() <= 1, "{} samples", tune.len());
        let wind = ghost_wind();
        assert_eq!(wind.len(), (4.0 * RATE) as usize);
        for (name, s) in [("tune", tune), ("wind", wind)] {
            let peak = s.iter().fold(0.0f32, |p, x| p.max(x.abs()));
            assert!(peak > 0.1 && peak <= 0.9001 && s.iter().all(|x| x.is_finite()), "{name} peak {peak}");
        }
    }

    #[test]
    fn the_goose_recording_is_read_and_both_moods_loop_at_its_length() {
        let rec = goose_recording().expect("the recording is 16-bit PCM");
        assert!(rec.len() > 5 * SAMPLE_RATE as usize);
        let (alone, wind) = (geese(0), geese(1));
        assert_eq!(alone.len(), wind.len());
        assert_eq!(alone.len(), rec.len() - (0.5 * RATE) as usize);
        for s in [alone, wind] {
            let peak = s.iter().fold(0.0f32, |p, x| p.max(x.abs()));
            assert!(peak > 0.2 && peak <= 0.9001 && s.iter().all(|x| x.is_finite()), "peak {peak}");
        }
    }

    #[test]
    fn a_looping_voice_fades_in_and_out() {
        let mut v = VoiceState {
            make: Arc::new(Box::new(Vec::new)),
            samples: Arc::new(OnceLock::from(vec![0.5f32; 1000])),
            generating: Arc::new(AtomicBool::new(true)),
            loops: true,
            playing: true,
            pos: 0.0,
            gain: 1.0,
            pan: 0.0,
            applied_gain: 0.0,
            applied_pan: 0.0,
            rate: 1.0,
        };
        let mut acc = vec![0.0f32; 4096];
        mix_into(&mut v, &mut acc, 2048, 1.0);
        // gain ramps from 0, so the first frame is silent and the last is loud; centred pan is equal on both sides
        assert_eq!(acc[0], 0.0);
        assert!((acc[4094] - acc[4095]).abs() < 1e-6 && acc[4094] > 0.3);
        assert!(v.playing, "a loop keeps playing past its end");
    }
}
