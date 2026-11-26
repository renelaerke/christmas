//! The orange snow plow clearing the panel when the snow gets high, alternating direction each run. Snow it
//! scrapes up builds a growing pile in front of the blade and is thrown up as chunks. The truck is driven in global
//! coordinates (`figures.rs`), so one plow drives on across neighbouring screens. Ported from `src/Layer.cs`.

use cairo::LineCap;

use super::draw::*;
use super::elves::ElfState;
use super::{blend_leaf, heap_at, leaf_sprite, Layer, SceneState, HEAP_STEP, LEAF_COLOURS};
use crate::figures::{PlowRun, PLOW_SCALE};

pub(super) struct PlowBit {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: f32,
    max: f32,
    size: f32,
    smoke: bool,
    /// Which leaf it is, in the autumn theme.
    kind: usize,
}

impl PlowBit {
    /// A chunk of snow thrown up (from the snowman the plow runs down, `build.rs`).
    pub(super) fn chunk(x: f32, y: f32, vx: f32, vy: f32, size: f32) -> PlowBit {
        PlowBit { x, y, vx, vy, life: 2.0, max: 2.0, size, smoke: false, kind: 0 }
    }
}

/// The plow as this screen sees it: x in screen coordinates.
struct Here {
    x: f32,
    dir: f32,
    wheel: f32,
    pushed: f32,
}

impl Layer {
    fn plow_here(&self, plow: Option<&PlowRun>) -> Option<Here> {
        let p = plow.filter(|p| p.active && p.members.contains(&self.index))?;
        Some(Here { x: p.gx - self.rect.x as f32, dir: p.dir, wheel: p.wheel, pushed: p.pushed })
    }

    fn plow_on_screen(&self, h: &Here) -> bool {
        let m = 140.0 * self.s * PLOW_SCALE;
        h.x > -m && h.x < self.w as f32 + m
    }

    fn plow_pile_height(&self, pushed: f32) -> f32 {
        (4.0 + (pushed / self.s).sqrt() * 0.3).min(34.0)
    }

    /// True while the truck is on this screen (the ground is then redrawn every frame).
    pub(super) fn plow_is_here(&self, st: &SceneState) -> bool {
        self.plow_here(st.plow).is_some_and(|h| self.plow_on_screen(&h))
    }

    /// True while snow chunks or smoke from the plow are still flying here (needs more frames).
    pub fn is_busy(&self) -> bool {
        !self.plow_bits.is_empty()
    }

    /// Snow scraped up on this screen since the last call; the controller adds it to the run.
    pub fn take_pushed(&mut self) -> f32 {
        std::mem::take(&mut self.plow_pushed)
    }

    pub(super) fn update_plow(&mut self, dt: f32, st: &SceneState) {
        let s = self.s;
        let sc = s * PLOW_SCALE;
        let here = self.plow_here(st.plow);
        if let Some(h) = &here {
            // Everything between the edge where the plow entered this screen and the blade stays scraped down.
            let w = self.w as f32;
            let blade = h.x + h.dir * 72.0 * sc;
            let residue = 1.5 * s;
            let from = if h.dir > 0.0 { 0.0 } else { w };
            if (h.dir > 0.0 && blade > 0.0) || (h.dir < 0.0 && blade < w) {
                let i0 = (from.min(blade).max(0.0) / HEAP_STEP as f32) as usize;
                let i1 = ((w.min(from.max(blade)) / HEAP_STEP as f32) as usize).min(self.heap.len() - 1);
                for hp in &mut self.heap[i0..=i1] {
                    if *hp > residue {
                        self.plow_pushed += *hp - residue;
                        *hp = residue;
                    }
                }
            }
        }
        if let Some(h) = here.filter(|h| self.plow_on_screen(h)) {
            let gy = self.ground_y - heap_at(&self.heap, h.x) + s;
            let ph = self.plow_pile_height(h.pushed);
            if st.halloween {
                if ph > 5.0 {
                    self.plow_chunk_acc += dt * if st.ghosts_blow { 16.0 } else { 10.0 };
                    while self.plow_chunk_acc >= 1.0 {
                        self.plow_chunk_acc -= 1.0;
                        let r = &mut self.rng;
                        let bit = if st.ghosts_blow {
                            // blown up and on ahead of the ghosts, to whirl away
                            PlowBit {
                                x: h.x + h.dir * (62.0 + r.f() * 40.0) * sc,
                                y: gy - (2.0 + r.f() * 16.0) * sc,
                                vx: h.dir * (150.0 + r.f() * 170.0) * s,
                                vy: -(130.0 + r.f() * 170.0) * s,
                                life: 2.2,
                                max: 2.2,
                                size: (3.5 + r.f() * 2.5) * s,
                                smoke: false,
                                kind: r.range(0, 1000) as usize,
                            }
                        } else {
                            // swept up by the witch's broom, flying back over the cat into the cauldron
                            PlowBit {
                                x: h.x + h.dir * (92.0 + r.f() * 14.0) * sc,
                                y: gy - (2.0 + r.f() * 6.0) * sc,
                                vx: -h.dir * (80.0 + r.f() * 70.0) * s,
                                vy: -(150.0 + r.f() * 70.0) * s,
                                life: 1.6,
                                max: 1.6,
                                size: (3.5 + r.f() * 2.5) * s,
                                smoke: false,
                                kind: r.range(0, 1000) as usize,
                            }
                        };
                        self.plow_bits.push(bit);
                    }
                }
            } else if st.muertos || st.karneval() {
                // the broom: petals are swept up and fly back over the donkey into the cart
                // (and carnival's street sweepers do the same with the confetti)
                if ph > 5.0 {
                    self.plow_chunk_acc += dt * 10.0;
                    while self.plow_chunk_acc >= 1.0 {
                        self.plow_chunk_acc -= 1.0;
                        let r = &mut self.rng;
                        self.plow_bits.push(PlowBit {
                            x: h.x + h.dir * (90.0 + r.f() * 14.0) * sc,
                            y: gy - (2.0 + r.f() * 6.0) * sc,
                            vx: -h.dir * (70.0 + r.f() * 70.0) * s,
                            vy: -(150.0 + r.f() * 70.0) * s,
                            life: 1.6,
                            max: 1.6,
                            size: (3.0 + r.f() * 2.0) * s,
                            smoke: false,
                            kind: r.range(0, 1000) as usize,
                        });
                    }
                }
            } else if st.autumn || st.nytaar {
                // the leaf collector (and New Year's street sweeper with its confetti): leaves whirl up around its nozzle and are left behind in the air for a moment
                if ph > 6.0 {
                    self.plow_chunk_acc += dt * 14.0;
                    while self.plow_chunk_acc >= 1.0 {
                        self.plow_chunk_acc -= 1.0;
                        let r = &mut self.rng;
                        self.plow_bits.push(PlowBit {
                            x: h.x + h.dir * (58.0 + r.f() * 26.0) * sc,
                            y: gy - (2.0 + r.f() * 10.0) * sc,
                            vx: h.dir * (r.f() - 0.35) * 110.0 * s,
                            vy: -(90.0 + r.f() * 150.0) * s,
                            life: 2.0,
                            max: 2.0,
                            size: (4.0 + r.f() * 3.0) * s,
                            smoke: false,
                            kind: r.range(0, 1000) as usize,
                        });
                    }
                }
            } else if ph > 10.0 {
                self.plow_chunk_acc += dt * 30.0;
                while self.plow_chunk_acc >= 1.0 {
                    self.plow_chunk_acc -= 1.0;
                    let r = &mut self.rng;
                    self.plow_bits.push(PlowBit {
                        x: h.x + h.dir * (70.0 + r.f() * ph) * sc,
                        y: gy - ph * sc,
                        vx: h.dir * (80.0 + r.f() * 140.0) * s,
                        vy: -(60.0 + r.f() * 140.0) * s,
                        life: 2.0,
                        max: 2.0,
                        size: (1.5 + r.f() * 2.5) * s,
                        smoke: false,
                        kind: 0,
                    });
                }
            }
            self.plow_smoke_timer -= dt;
            // (a donkey makes no smoke, nor do a witch or ghosts, nor carnival's street sweepers)
            if self.plow_smoke_timer <= 0.0 && !st.muertos && !st.halloween && !st.nytaar && !st.karneval() {
                self.plow_smoke_timer = 0.2;
                self.plow_bits.push(PlowBit {
                    x: h.x - h.dir * 2.0 * sc,
                    y: gy - 76.0 * sc,
                    vx: -h.dir * 25.0 * s,
                    vy: -30.0 * s,
                    life: 1.6,
                    max: 1.6,
                    size: 5.0 * s,
                    smoke: true,
                    kind: 0,
                });
            }
            // the elves wave at the truck as it passes
            for e in &mut self.elves {
                if e.state != ElfState::Wave && (e.x - h.x).abs() < 140.0 * s {
                    e.state = ElfState::Wave;
                    e.state_timer = 1.5;
                }
            }
            if (st.time * 2.0) as i64 != ((st.time - dt as f64) * 2.0) as i64 {
                crate::log::debug(&format!(
                    "plow on screen x={}: x={} gy={} pushed={}",
                    self.rect.x, h.x as i32, gy as i32, h.pushed as i32
                ));
            }
        }

        let (ground, heap) = (self.ground_y, &self.heap);
        self.plow_bits.retain_mut(|b| {
            b.life -= dt;
            b.x += b.vx * dt;
            b.y += b.vy * dt;
            if b.smoke {
                b.size += 6.0 * s * dt;
            } else {
                b.vy += 420.0 * s * dt;
            }
            !(b.life <= 0.0 || (!b.smoke && b.vy > 0.0 && b.y >= ground - heap_at(heap, b.x)))
        });
    }

    pub(super) fn draw_plow(&mut self, st: &SceneState) {
        if st.leaves() && self.plow_bits.iter().any(|b| !b.smoke) {
            // the leaves the leaf collector whirls up, turning as they fly (straight into the pixels, as the
            // falling ones)
            self.canvas.surface.flush();
            let (w, h) = (self.w, self.h);
            for i in 0..self.plow_bits.len() {
                let b = &self.plow_bits[i];
                if b.smoke {
                    continue;
                }
                let (x, y, size, rot, kind) = (b.x, b.y, b.size * 2.6, b.life * 7.0 + b.kind as f32, b.kind);
                self.mark(x - size * 0.71, y - size * 0.71, size * 1.42, size * 1.42);
                let Some(sprite) = self.leaf_sprites.get(leaf_sprite(kind)) else { continue };
                blend_leaf(&mut self.canvas.pixels[..], w, h, sprite, x, y, size, rot, 255);
            }
            self.canvas.surface.mark_dirty();
        }
        for i in 0..self.plow_bits.len() {
            let b = &self.plow_bits[i];
            if st.leaves() && !b.smoke {
                continue;
            }
            let (x, y, size) = (b.x, b.y, b.size);
            let col = if b.smoke { ((90.0 * b.life / b.max) as u8, 120, 120, 125) } else { (235, 250, 252, 255) };
            self.mark(x - size, y - size, size * 2.0, size * 2.0);
            let (x, y, size) = (x as f64, y as f64, size as f64);
            fill_ellipse(&self.canvas.cr, col, x - size, y - size, size * 2.0, size * 2.0);
        }
        let Some(h) = self.plow_here(st.plow).filter(|h| self.plow_on_screen(h)) else { return };

        let s = self.s;
        let sc = s * PLOW_SCALE;
        let gy = self.ground_y - heap_at(&self.heap, h.x) + s;
        let ph = self.plow_pile_height(h.pushed) as f64;
        self.mark(h.x - 130.0 * sc, gy - 100.0 * sc, 260.0 * sc, 106.0 * sc);

        let cr = &self.canvas.cr;
        let saved = cr.matrix();
        cr.translate(h.x as f64, gy as f64);
        cr.scale((h.dir * sc) as f64, sc as f64);
        if st.muertos {
            super::muertos::petal_cart(cr, ph, h.wheel as f64);
            cr.set_matrix(saved);
            return;
        }
        if st.halloween {
            if st.ghosts_blow {
                super::halloween::ghost_blowers(cr, ph, h.wheel as f64);
            } else {
                super::halloween::witch_sweeper(cr, ph, h.wheel as f64);
            }
            cr.set_matrix(saved);
            return;
        }
        if st.nytaar {
            super::nytaar::sweeper(cr, ph, h.wheel as f64);
            cr.set_matrix(saved);
            return;
        }
        if st.karneval() {
            super::karneval::street_sweepers(cr, ph, h.wheel as f64);
            cr.set_matrix(saved);
            return;
        }
        if st.autumn {
            leaf_collector(cr, ph, h.wheel as f64, st.time);
            cr.set_matrix(saved);
            return;
        }

        let orange = rgb(235, 130, 20);
        let orange_dark = rgb(185, 95, 10);
        let dark = rgb(50, 50, 55);
        let grey = rgb(110, 110, 115);
        let glass = rgb(175, 210, 235);

        // exhaust stack
        fill_rect(cr, grey, -4.0, -76.0, 4.0, 30.0);

        // salt spreader at the back, with a spinning disc
        fill_rect(cr, grey, -92.0, -32.0, 12.0, 16.0);
        let sa = (h.wheel * 2.0) as f64;
        line(cr, rgb(70, 70, 75), 2.0, LineCap::Butt, -86.0 - sa.cos() * 6.0, -14.0, -86.0 + sa.cos() * 6.0, -14.0);

        // dump body with ribs and a reflective stripe
        fill_rect(cr, orange, -80.0, -50.0, 74.0, 36.0);
        fill_rect(cr, orange_dark, -82.0, -53.0, 78.0, 5.0);
        for rx in [-62.0, -44.0, -26.0] {
            line(cr, orange_dark, 2.0, LineCap::Butt, rx, -48.0, rx, -16.0);
        }

        // cab
        fill_polygon(cr, orange, &[(-2.0, -14.0), (-2.0, -64.0), (26.0, -64.0), (40.0, -44.0), (43.0, -14.0)]);
        fill_polygon(cr, glass, &[(14.0, -59.0), (25.0, -59.0), (36.0, -43.0), (14.0, -43.0)]);
        fill_rect(cr, glass, 1.0, -59.0, 10.0, 16.0);
        line(cr, orange_dark, 1.2, LineCap::Butt, 12.0, -60.0, 12.0, -16.0);
        fill_rect(cr, dark, 4.0, -38.0, 5.0, 2.0);
        fill_rect(cr, (230, 255, 255, 255), -80.0, -26.0, 123.0, 3.0);
        fill_ellipse(cr, rgb(255, 245, 190), 38.0, -26.0, 5.0, 5.0);

        // amber beacon on the roof, flashing
        fill_rect(cr, dark, 12.0, -68.0, 10.0, 4.0);
        let flash = 0.5 + 0.5 * (st.time * 12.0).sin();
        fill_ellipse(cr, ((150.0 * flash) as u8, 255, 170, 0), 3.0, -82.0, 28.0, 24.0);
        fill_ellipse(cr, rgb((200.0 + 55.0 * flash) as u8, (120.0 + 60.0 * flash) as u8, 0), 13.0, -74.0, 8.0, 7.0);

        // chassis and wheels with rotating spokes
        fill_rect(cr, dark, -86.0, -16.0, 132.0, 7.0);
        for wx in [-58.0, -32.0, 26.0] {
            fill_ellipse(cr, rgb(30, 30, 32), wx - 10.0, -20.0, 20.0, 20.0);
            fill_ellipse(cr, rgb(160, 160, 165), wx - 5.0, -15.0, 10.0, 10.0);
            for k in 0..3 {
                let a = h.wheel as f64 + k as f64 * std::f64::consts::FRAC_PI_3;
                let (dx, dy) = (a.cos() * 5.0, a.sin() * 5.0);
                line(cr, rgb(60, 60, 65), 1.6, LineCap::Butt, wx - dx, -10.0 - dy, wx + dx, -10.0 + dy);
            }
        }

        // snow pile in front of the blade
        cr.new_path();
        cr.move_to(56.0, 1.0);
        cr.curve_to(60.0, -ph, 74.0 + ph * 0.6, -ph * 0.95, 72.0 + ph * 1.6, 1.0);
        cr.close_path();
        set(cr, (250, 250, 252, 255));
        let _ = cr.fill_preserve();
        stroke(cr, (120, 170, 200, 230), 1.0, LineCap::Butt);

        // plow arm and curved yellow blade with black warning stripes
        line(cr, rgb(80, 80, 85), 3.0, LineCap::Butt, 42.0, -12.0, 55.0, -16.0);
        let blade = |cr: &cairo::Context| {
            cr.new_path();
            cr.move_to(54.0, -38.0);
            cr.curve_to(66.0, -30.0, 70.0, -14.0, 68.0, 2.0);
            cr.line_to(56.0, 2.0);
            cr.curve_to(58.0, -12.0, 54.0, -28.0, 50.0, -38.0);
            cr.close_path();
        };
        blade(cr);
        set(cr, rgb(250, 195, 30));
        let _ = cr.fill_preserve();
        cr.save().ok();
        cr.clip();
        let mut sy = -44.0;
        while sy < 8.0 {
            line(cr, rgb(40, 40, 40), 3.0, LineCap::Butt, 46.0, sy, 74.0, sy + 14.0);
            sy += 9.0;
        }
        cr.restore().ok();
        blade(cr);
        stroke(cr, rgb(130, 95, 10), 1.2, LineCap::Butt);
        cr.set_matrix(saved);
    }
}

/// Autumn's form of the snow plow (`DrawLeafCollector` on Windows): the same truck in green, with a suction nozzle
/// and hose in place of the blade, and an open body heaped with leaves in place of the salt spreader. `ph` is how
/// much it has taken (the height the snow pile in front of the blade would have). Drawn in the plow's frame.
fn leaf_collector(cr: &cairo::Context, ph: f64, wheel: f64, time: f64) {
    let (o, od) = (rgb(72, 138, 78), rgb(44, 96, 52));
    let (dark, grey, glass) = (rgb(50, 50, 55), rgb(110, 110, 115), rgb(175, 210, 235));
    // exhaust stack
    fill_rect(cr, grey, -4.0, -76.0, 4.0, 30.0);
    // the hose rises in front of the cab and bends back over it into the body (drawn first, so the cab hides part
    // of it)
    for (col, width) in [(rgb(38, 38, 42), 8.0), (rgb(90, 90, 96), 1.5)] {
        cr.new_path();
        cr.move_to(62.0, -12.0);
        cr.curve_to(66.0, -62.0, 38.0, -80.0, -10.0, -56.0);
        stroke(cr, col, width, LineCap::Round);
    }
    // leaves heaped over the edge of the body
    let n = LEAF_COLOURS.len();
    for (i, hx) in [-74.0, -63.0, -52.0, -41.0, -30.0, -19.0].into_iter().enumerate() {
        let odd = (i % 2) as f64 * 3.0;
        fill_ellipse(cr, LEAF_COLOURS[(i * 2) % n], hx - 8.0, -62.0 + odd, 16.0, 12.0);
        fill_ellipse(cr, LEAF_COLOURS[(i * 2 + 1) % n], hx - 2.0, -59.0 - odd, 12.0, 9.0);
    }
    // dump body with ribs and a reflective stripe
    fill_rect(cr, o, -80.0, -50.0, 74.0, 36.0);
    fill_rect(cr, od, -82.0, -53.0, 78.0, 5.0);
    for rx in [-62.0, -44.0, -26.0] {
        line(cr, od, 2.0, LineCap::Butt, rx, -48.0, rx, -16.0);
    }
    // cab
    fill_polygon(cr, o, &[(-2.0, -14.0), (-2.0, -64.0), (26.0, -64.0), (40.0, -44.0), (43.0, -14.0)]);
    fill_polygon(cr, glass, &[(14.0, -59.0), (25.0, -59.0), (36.0, -43.0), (14.0, -43.0)]);
    fill_rect(cr, glass, 1.0, -59.0, 10.0, 16.0);
    line(cr, od, 1.2, LineCap::Butt, 12.0, -60.0, 12.0, -16.0);
    fill_rect(cr, dark, 4.0, -38.0, 5.0, 2.0);
    fill_rect(cr, (230, 255, 255, 255), -80.0, -26.0, 123.0, 3.0);
    fill_ellipse(cr, rgb(255, 245, 190), 38.0, -26.0, 5.0, 5.0);
    // amber beacon on the roof, flashing
    fill_rect(cr, dark, 12.0, -68.0, 10.0, 4.0);
    let flash = 0.5 + 0.5 * (time * 12.0).sin();
    fill_ellipse(cr, ((150.0 * flash) as u8, 255, 170, 0), 3.0, -82.0, 28.0, 24.0);
    fill_ellipse(cr, rgb(255, (200.0 + 55.0 * flash) as u8, (120.0 + 60.0 * flash) as u8), 13.0, -74.0, 8.0, 7.0);
    // chassis and wheels with rotating spokes
    fill_rect(cr, dark, -86.0, -16.0, 132.0, 7.0);
    for wx in [-58.0, -32.0, 26.0] {
        fill_ellipse(cr, rgb(30, 30, 32), wx - 10.0, -20.0, 20.0, 20.0);
        fill_ellipse(cr, rgb(160, 160, 165), wx - 5.0, -15.0, 10.0, 10.0);
        for k in 0..3 {
            let a = wheel + k as f64 * std::f64::consts::FRAC_PI_3;
            let (dx, dy) = (a.cos() * 5.0, a.sin() * 5.0);
            line(cr, rgb(60, 60, 65), 1.6, LineCap::Butt, wx - dx, -10.0 - dy, wx + dx, -10.0 + dy);
        }
    }
    // the leaves it is about to take, and the wide nozzle at the ground with a warning stripe
    for (i, ax) in [74.0, 82.0, 90.0, 98.0].into_iter().enumerate() {
        if ((i * 7) as f64) < ph {
            fill_ellipse(cr, LEAF_COLOURS[i % n], ax - 7.0, -7.0 - (i % 2) as f64 * 3.0, 14.0, 9.0);
        }
    }
    line(cr, rgb(80, 80, 85), 3.0, LineCap::Butt, 42.0, -12.0, 56.0, -14.0);
    fill_polygon(cr, dark, &[(54.0, -18.0), (70.0, -18.0), (80.0, 2.0), (50.0, 2.0)]);
    fill_rect(cr, rgb(250, 195, 30), 51.0, -3.0, 28.0, 3.0);
}
