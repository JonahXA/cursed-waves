# Cursed Waves — game spec

Working title. The published name gets chosen deliberately before launch.

Wave-based tower defense with one hook: between waves you choose to bank your
rewards or take a **cursed wave** at multiplied payout against nastier enemies.

---

## Why tower defense

- **Evergreen and large.** Tower Defense Simulator, Toilet Tower Defense and Anime
  Vanguards have held tens of thousands of concurrent players for years. The genre
  does not depend on a trend cycle.
- **Fully solo.** PvE waves work at 1 concurrent player, which is the hard filter a
  new game cannot dodge.
- **It is a systems game.** Wave scaling, tower stats, targeting, enemy HP curves and
  economy are tables and math, not authored art.
- **Most art-forgiving proven genre.** Towers and enemies are small, seen from above,
  and read by silhouette and colour. Deliberate low-poly looks intentional here in a
  way it does not in most genres.
- **Session length.** The deciding factor. Gate 0 wants 8+ minute average sessions and
  a TD run is naturally 5–15 minutes of *continuous* engagement — far easier to hold
  than a loop built around waiting.

## Why it is not a generic clone

The research is explicit that the failure mode is not picking a popular genre, it is
shipping the weakest generic version of one. The differentiator here:

**The cursed-wave bet.** After each wave you choose:

- **Bank** — keep your cash, next wave is normal.
- **Curse it** — next wave pays 2–3× but enemies come faster, tougher, or with a
  modifier. Curses stack while you keep accepting them.

This makes the between-wave moment a decision instead of a pause, and it gives every
run a story ("I was four curses deep on wave 12"). Same push-your-luck engine designed
for Concept A, moved into a genre with much better retention mechanics.

---

## Core loop

1. Spawn on a map with a fixed enemy path and a base with health.
2. Place towers with in-run cash on buildable ground.
3. A wave spawns. Enemies walk the path. Towers auto-target and fire.
4. Enemies that reach the base cost you base health. Zero health ends the run.
5. Kills pay cash. Wave completion pays a bonus.
6. **Between waves: bank or curse.**
7. Upgrade towers, place more, repeat.
8. Run ends on death or after the final wave. Persistent XP and unlocks carry over.

**Time to first action: under 30 seconds.** Player spawns next to a highlighted build
pad with enough cash for one tower and a single prompt. Placing that tower is the
first thing they do, before any wave arrives.

---

## Content — all data, no authored art

### Towers

| Tower | Role | Cost | Notes |
|---|---|---|---|
| Pea | starter, single target | 100 | always unlocked |
| Splash | area damage | 250 | weak vs armour |
| Frost | slows | 200 | no damage, pure utility |
| Sniper | high damage, slow, long range | 400 | ignores armour |

Each has three upgrade tiers. Upgrades are stat multipliers from a table, not new
models — a tier-3 tower is the same mesh, scaled and recoloured.

### Enemies

| Enemy | Trait |
|---|---|
| Grunt | baseline |
| Runner | fast, low HP |
| Tank | slow, high HP, armoured |
| Swarm | spawns in packs |
| Boss | every 10th wave, high HP, immune to slow |

### Curses

| Curse | Effect | Payout |
|---|---|---|
| Haste | enemies +40% speed | ×2 |
| Armour | enemies take 30% less damage | ×2 |
| Horde | +60% enemy count | ×2.5 |
| Fog | tower range −25% | ×2.5 |
| Blight | base takes double damage from leaks | ×3 |

Curses stack multiplicatively on payout and additively on difficulty. This is the
tuning surface that decides whether the game is tense or unfair.

---

## Starting numbers

Tuning targets, not truths.

| Parameter | Start |
|---|---|
| Base health | 100 |
| Starting cash | 150 |
| Wave interval (build time) | 15s |
| Enemy HP scaling | ×1.18 per wave |
| Enemy count scaling | +2 per wave |
| Cash per kill | 8, scaling ×1.1 per wave |
| Wave clear bonus | 50 + 10/wave |
| Boss every | 10 waves |

**The tuning goal is that curses are genuinely tempting and genuinely dangerous.** If
players always curse, the payout is too high. If they never curse, it is too low. Watch
the distribution of curses accepted per run — a spike at zero or at max means it is
broken.

---

## Data model

Extends the phase0 `Profile`. Run state is in-memory and deliberately not persisted —
a run is meant to be lost.

```
persistent: coins, xp, level, unlockedTowers, stats
stats: runsPlayed, bestWave, bestRun, totalCurses, deathsWhileCursed
```

`deathsWhileCursed` against `runsPlayed` is the instrument for whether the bet is
tuned. If nearly every run ends on a cursed wave, the curse is a trap rather than a
decision, and players will learn to never take it.

---

## Build order

1. Map, path, base health, spawner
2. Towers: placement, targeting, firing, damage
3. Waves: scaling, enemy types, clear detection
4. Economy: kill cash, wave bonus, tower costs, upgrades
5. **The curse bet** — the hook, built early enough to be tuned properly
6. Persistence, XP, unlocks
7. Onboarding — the first 60 seconds
8. Sound and particles
9. Monetization
10. Balance pass

---

## What would kill this

- **Curses are never worth taking.** Then it is a generic TD and the differentiator is
  dead. Watch curse-accept rate.
- **Runs are too long.** A 40-minute run is bad for session metrics *and* bad for
  retention — players need to finish and come back, not grind.
- **It reads as a generic clone in the first five seconds.** The curse decision has to
  be visible in the thumbnail and the first minute.

Kill criteria unchanged: see `METRICS.md`.
