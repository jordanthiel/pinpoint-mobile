# Golf stats tracking strategy

## Objective

Build a shot-level analytics system that answers three questions after every round:

1. **Where did I gain or lose shots?**
2. **Why did that happen?**
3. **What should I practice or change next?**

The system should be organized around **strokes gained versus a scratch golfer**, not raw totals or PGA Tour comparisons. Traditional stats such as fairways, greens in regulation, and putts remain useful, but only as supporting diagnostics.

**Current reference snapshot:** 29 scored rounds, 79.6 scoring average, 39.4% fairways, 42.1% GIR, and 32.0 putts per round. Treat this as a starting snapshot and replace it with rolling app data as new rounds are recorded.

---

## The central framework: strokes gained

For each shot:

```text
Strokes gained = Expected strokes from start
               - Expected strokes from finish
               - 1
```

Expected strokes must come from a baseline table indexed by:

- Distance to the hole
- Lie: tee, fairway, rough, recovery, bunker, green, or penalty
- Benchmark skill level, ideally scratch

Every shot is assigned to one of four categories:

- **Off the tee:** Tee shots on par 4s and par 5s
- **Approach:** Full shots intended to reach or materially advance toward the green
- **Around the green:** Non-putts close to the green, generally inside 50 yards for this app
- **Putting:** All shots from the putting surface

The category totals sum to **SG: Total**.

### Why this should lead the product

Raw stats treat unlike shots as equal. A fairway hit with a 4-iron that leaves 220 yards is not necessarily better than a driver in light rough that leaves 130 yards. A two-putt from 50 feet is excellent; a two-putt from four feet is not. Strokes gained handles that context automatically.

Research associated with Mark Broadie's work suggests that, in a roughly ten-shot scoring gap, only about 1.5 shots come from putting while roughly 6.5 come from shots outside 100 yards. That makes ball-striking—especially approach play—the main improvement lever, while putting remains important but should not dominate practice planning.

---

## The Core 11

These are the home-screen metrics. Together they provide most of the useful signal without overwhelming the golfer.

### 1. SG: Total versus scratch

**Definition:** Sum of strokes gained for every shot relative to a scratch baseline.

**Use:** The headline measure of overall performance and progress. Show per round, rolling five rounds, rolling ten rounds, and season.

**Target:** Trend toward 0.0 per round versus scratch.

**Inputs:** Start distance and lie, finish distance and lie, penalties, holed status.

### 2. SG: Off the tee

**Definition:** Strokes gained on par-4 and par-5 tee shots.

**Use:** Separates useful distance from reckless distance. This is more informative than fairway percentage alone.

**Target:** Trend toward 0.0 versus scratch.

**Inputs:** Club, start and finish coordinates, finish lie, penalty/recovery state.

### 3. SG: Approach

**Definition:** Strokes gained on full shots toward the green.

**Use:** Usually the largest separator between a low-80s player and scratch. This should be the first category investigated when total SG is weak.

**Target:** Trend toward 0.0 versus scratch.

**Inputs:** Club, start distance and lie, finish distance and lie, green-hit flag.

### 4. SG: Around the green

**Definition:** Strokes gained on non-putts inside the app's short-game boundary, recommended at 50 yards.

**Use:** Measures actual conversion quality rather than relying only on scrambling percentage.

**Target:** Trend toward 0.0 versus scratch.

**Inputs:** Start distance and lie, finish distance and lie, strike quality.

### 5. SG: Putting

**Definition:** Strokes gained on all putts.

**Use:** Correctly values lag putting, short makes, and three-putts without the distortions of total putts.

**Target:** Trend toward 0.0 versus scratch.

**Inputs:** Start distance, finish distance, holed status.

### 6. Effective driving distance

**Definition:** Average driver distance on par 4s and par 5s, with penalties and recovery shots flagged rather than silently averaged in.

**Use:** Tracks whether speed and strike improvements produce useful course distance.

**Directional benchmark:** Published Arccos-derived figures place 10–14.9 handicaps near 223 yards, 5–9.9 near 234 yards, and 0–4.9 near 244 yards. A practical long-term target is 240-plus yards if it does not increase damaging misses.

**Inputs:** Club, shot distance, hole par, penalty/recovery flag.

### 7. Damaging-drive rate

**Definition:** Percentage of tee shots ending in a penalty or requiring a recovery shot.

**Use:** Big numbers often begin here. Keep penalty and recovery rates separate, then show the combined number.

**Directional benchmark:** Research citing Arccos data places 10–15 handicaps near 7% penalties plus 16% recovery situations. A useful target is below 12% combined.

**Inputs:** Tee-shot finish lie, penalty type, next-shot recovery flag.

### 8. GIR overall and by distance band

**Definition:** Greens in regulation, split by approach distance.

Recommended bands:

- Under 100 yards
- 100–124 yards
- 125–149 yards
- 150–174 yards
- 175–199 yards
- 200-plus yards

**Use:** Overall GIR is useful; banded GIR shows exactly where approach performance collapses.

**Directional target:** Move from the low-40% range toward 50% or better, while focusing on the weakest distance band.

**Inputs:** Approach distance, lie, shot number, green-hit flag, hole par.

### 9. Up-and-down percentage inside 50 yards

**Definition:** Percentage of missed-green situations inside 50 yards completed in two shots or fewer.

**Use:** The clearest short-game conversion measure.

**Directional benchmark:** Published Shot Scope figures are about 39% for a 10 handicap and 54% for scratch.

**Inputs:** Missed-green state, start distance and lie, subsequent shots to hole out.

### 10. Three-putt percentage

**Definition:** Percentage of holes with three or more putts.

**Use:** Captures preventable putting losses better than total putts.

**Directional benchmark:** Published Shot Scope figures place a 10 handicap near 7%. Use 4% or lower as a directional scratch-level target until a verified scratch-amateur baseline is available.

**Inputs:** Putt count and first-putt distance.

### 11. Double-bogey-or-worse rate

**Definition:** Percentage of holes scored at double bogey or worse.

**Use:** The best scoring-discipline KPI. The app should connect every double to its initiating cause.

**Inputs:** Hole score, par, penalties, shot sequence, lies, strike quality.

---

## Tier 2 diagnostics

Use these to explain *why* a Core 11 metric moved. They should sit one tap below the home dashboard.

### Driving

- **Playable tee-shot percentage:** Fairway, first cut, or clean rough with a normal next shot. More useful than fairway percentage alone.
- **Penalty rate:** OB, water, lost ball, or unplayable penalty per tee shot.
- **Recovery rate:** Tee shots requiring a punch-out or intentionally restricted next shot.
- **Dispersion width by club:** Left-to-right spread and a 50%/80% dispersion ellipse.
- **Miss direction:** Push, pull, slice, hook, and straight-block rates.
- **Strike-quality distribution:** Center, heel, toe, thin, heavy, or unknown.
- **Distance-versus-damage curve:** Driver distance plotted against SG: Off the Tee and damaging-drive rate.

### Approach

- **Proximity by distance band:** Use every approach, including misses—not GIR approaches only.
- **Median leave by band:** More resistant to one terrible outlier than average proximity.
- **Miss pattern:** Short, long, left, right, and short-sided.
- **Short-miss percentage:** A direct test of club selection and true carry knowledge.
- **50%-GIR distance:** The farthest distance from which the golfer hits at least half the greens.
- **Fairway-versus-rough split:** GIR, proximity, and SG from each lie.
- **Club-level performance:** Carry estimate, typical leave, GIR, dispersion, and SG per shot.

Directional approach benchmarks reported for a 10 handicap versus scratch are approximately:

| Start distance | 10 hcp | Scratch |
|---|---:|---:|
| 100–150 yd | 48 ft | 31 ft |
| 150–200 yd | 70 ft | 43 ft |
| 200+ yd | 92 ft | 56 ft |

These are useful product defaults, not promises. Course setup, lie, weather, and sample size matter.

### Around the green

- **Proximity by distance:** Under 10, 10–19, 20–29, and 30–50 yards.
- **Performance by lie:** Fringe, fairway, rough, bunker, and recovery.
- **Two-chip rate:** Two or more short-game shots before reaching the green.
- **Duff/blade rate:** Poor-strike short-game shots, supported by manual strike-quality tagging.
- **Sand-save percentage:** Holed in two shots or fewer after a greenside bunker shot.
- **Short-sided conversion:** Up-and-down rate when the miss leaves little green to work with.

### Putting

- **Make percentage by band:** 0–2, 3–5, 6–9, 10–15, 16–25, and 25-plus feet.
- **Lag success:** Percentage of first putts from 25-plus feet finishing inside three feet.
- **Average second-putt distance:** More actionable than total putts.
- **Three-putt origin:** First-putt distance for every three-putt.
- **Putts per GIR:** A better traditional efficiency measure than putts per round.
- **Miss tendency:** Short/long and left/right when the user can reliably record it.

---

## Tier 3 deep dives

Add these only after shot capture and the first two tiers are reliable:

- SG by club, hole, course, and lie
- Expected score versus actual score by hole
- First-putt-distance distribution
- Par-5 birdie conversion
- Bounce-back percentage after bogey or worse
- GIR+1 percentage on difficult courses
- Strike-quality distribution by club
- Penalty autopsy by cause and club
- Approach target versus actual finish
- DECADE-style strategy adherence
- Range-to-course carry and dispersion comparison
- Performance by wind, temperature, elevation, and turf when reliable data exists

Do not let Tier 3 clutter the daily dashboard. These belong in filters, club profiles, course reports, and periodic reviews.

---

## Dashboard design

### Home: “Where did the shots go?”

Show:

1. Score and SG: Total versus scratch
2. Four SG category bars
3. Change versus rolling ten-round average
4. One positive takeaway
5. One highest-priority leak
6. One recommended practice focus

The app should avoid generating five simultaneous priorities. Pick the leak with the greatest combination of:

```text
Priority score = Strokes lost
               × Recurrence
               × Controllability
               × Confidence in sample
```

### Approach dashboard

- GIR by distance band
- Median and average proximity by band
- Short/long/left/right miss map
- 50%-GIR distance
- SG: Approach trend
- Best and worst approach clubs

### Driving dashboard

- SG: Off the Tee trend
- Effective distance by club
- Playable, recovery, and penalty percentages
- Shot scatter with 50% and 80% ellipses
- Miss direction and strike-quality distribution
- Distance-versus-damage chart

### Short-game dashboard

Use a funnel:

```text
Missed green
    --> Short-game starting lie/distance
    --> Proximity after first short-game shot
    --> Up-and-down result
    --> Two-chip or poor-strike outcome
```

Show the funnel overall and split by fairway/fringe, rough, and bunker.

### Putting dashboard

- SG: Putting trend
- Make-rate curve by distance
- Three-putt rate and its first-putt-distance distribution
- Lag-putt success from 25-plus feet
- Putts per GIR

### Big-number autopsy

Every double bogey or worse should receive a primary cause:

- Tee penalty
- Tee recovery
- Approach penalty
- Short-sided approach miss
- Poor short-game strike
- Two-chip
- Three-putt
- Four-putt
- Other

Also store secondary causes. A double might begin with a recovery drive and end with a three-putt; the app should preserve both while identifying the first meaningful error.

### Trends and benchmarks

For every major metric, offer:

- Last round
- Rolling 5 rounds
- Rolling 10 rounds
- Current season
- Personal best rolling period
- Comparison with current-handicap and scratch baselines

Avoid declaring a trend from a single round. Show a low-sample warning until a metric has enough opportunities to be useful.

---

## Shot-level data model

### Required fields

Each shot should store:

- Round, course, hole, par, and shot number
- Club
- Start and finish GPS coordinates
- Start and finish distance to the pin
- Start and finish lie
- Penalty type and strokes
- Holed flag
- Timestamp

### Strongly recommended fields

- Intended target coordinates
- Strike quality: pure, acceptable, heel, toe, thin, heavy, topped, bladed
- Shot shape: straight, draw, fade, pull, push, hook, slice
- Recovery-required flag
- Short-sided flag
- Wind and temperature when available from a trustworthy source
- Manual confidence/correction flag

### Derived fields

Compute rather than ask the golfer to enter:

- Shot distance
- Offline distance from intended line
- Distance remaining
- SG value and category
- GIR and GIR distance band
- Miss direction
- Playable/recovery/damaging result
- Up-and-down opportunity and result
- First-putt distance
- Three-putt flag
- Double-bogey cause

### Data-quality rules

- Let the golfer correct club, lie, and pin position after the round.
- Keep original sensor values and corrected values separately.
- Mark auto-detected versus manually confirmed fields.
- Exclude conceded or estimated shots from precision metrics unless labeled.
- Handle penalties explicitly; do not hide them inside shot distance.
- Preserve unfinished holes as incomplete rather than scoring them as failures.

---

## What to keep, demote, and avoid

### Keep

- **Score and handicap:** Essential outcomes, but lagging indicators.
- **GIR:** Keep overall and by distance band.
- **Fairways:** Keep, paired with club, distance, and playable-shot status.
- **Putts:** Keep as raw history, but emphasize putts per GIR and SG: Putting.
- **Scrambling:** Keep, split by distance and lie.

### Demote

- **Total putts:** A golfer who hits more greens may take more putts while scoring better.
- **Fairway percentage alone:** It ignores distance and quality of the next shot.
- **Average proximity alone:** It mixes incomparable starting distances and lies.
- **Up-and-down percentage alone:** A fringe chip and a 45-yard bunker shot are not equal tasks.
- **Birdies per round:** Useful as an outcome, poor as a diagnosis.

### Avoid

- A single “game score” with no explanation
- Benchmarking an amateur only against PGA Tour players
- Showing more than one decimal place for noisy amateur metrics
- Ranking clubs on tiny samples
- Treating manual strike-quality labels as objective launch-monitor data
- Practice advice driven by one bad round

---

## Practice decision engine

The analytics should produce a weekly plan, not merely charts.

### Step 1: Find the category leak

Use rolling ten-round SG versus scratch. Rank Off the Tee, Approach, Around the Green, and Putting by total strokes lost.

### Step 2: Find the repeated cause

Examples:

- **Off the tee:** Penalties, recoveries, short effective distance, or one-sided dispersion
- **Approach:** Weak distance band, short misses, poor performance from rough, or a specific club
- **Around green:** Poor strike, weak rough play, bunker issues, or poor 20–40-yard proximity
- **Putting:** Misses inside six feet, weak lag speed, or three-putts from a specific range

### Step 3: Separate skill from strategy

- **Skill issue:** Normal target, poor execution repeatedly
- **Strategy issue:** Wrong club, wrong target, unnecessary risk, or playing away from personal dispersion
- **Data issue:** Missing shot, bad lie classification, incorrect pin, or too few attempts

### Step 4: Prescribe one primary and one secondary focus

Example:

> **Primary:** Approach shots from 150–175 yards. You lose the most strokes here and miss short too often. Verify carry numbers and practice a stock 6-iron/7-iron window.
>
> **Secondary:** Eliminate tee penalties. Driver remains the default where the landing zone supports the 80% dispersion pattern; change target before changing club.

### Step 5: Measure whether practice transfers

Track the chosen diagnostic for the next five and ten rounds. Do not judge transfer only by score.

---

## Product roadmap

### Phase 1: Trustworthy capture

- Record every shot, club, location, lie, penalty, and putt distance
- Build post-round correction
- Calculate score, GIR, fairways, penalties, and putt bands
- Validate shot sequencing and unfinished-hole handling

**Exit criterion:** A golfer can reconstruct the round without unexplained or impossible shots.

### Phase 2: Core analytics

- Implement a licensed or defensible scratch SG baseline
- Calculate all four SG categories and SG: Total
- Add the Core 11
- Build rolling 5- and 10-round trends
- Add sample-size and data-quality warnings

**Exit criterion:** Category totals reconcile with the score differential within the baseline model.

### Phase 3: Diagnosis

- Proximity and GIR by band
- Driving damage and playable-shot rates
- Putting make and lag metrics
- Short-game funnel and two-chip rate
- Big-number autopsy

**Exit criterion:** Every major SG loss can be traced to a concrete pattern.

### Phase 4: Recommendations

- Generate one primary practice focus
- Separate strategy from execution
- Add club and course recommendations based on dispersion
- Measure five- and ten-round transfer

**Exit criterion:** Recommendations cite the exact shots and trends that produced them.

### Phase 5: Range and simulation integration

- Import carry, ball speed, launch, spin, and dispersion
- Compare range carry with on-course effective distance
- Link strike-quality patterns to on-course outcomes
- Build club-gapping and confidence profiles

---

## Recommended first release

The first version should contain:

- Shot capture and correction
- SG: Total and four SG categories versus scratch
- Effective driving distance
- Damaging-drive rate
- GIR by distance band
- Up-and-down percentage inside 50 yards
- Three-putt percentage
- Double-bogey autopsy
- Rolling five- and ten-round trends
- One recommended practice priority

Delay advanced weather, slope, green-reading, and strategy simulations until this foundation is accurate. A smaller trusted dataset is more valuable than a comprehensive dashboard built on bad shot locations.

---

## Operating principles

1. **Benchmark against the goal:** Scratch is the primary comparison; current-handicap peers provide context.
2. **Prioritize shots outside 100 yards:** Approach and driving normally deserve more practice time than putting.
3. **Driver is the default, not a commandment:** Use it when the landing area can contain the player's dispersion without bringing severe trouble into play.
4. **Be aggressive off the tee and conservative into greens:** Preserve useful distance, then shift approach targets toward the safe center of the green.
5. **Eliminate big numbers before chasing more birdies:** Penalties, recoveries, two-chips, and three-putts deserve explicit tracking.
6. **Use distributions, not only averages:** Median leave, dispersion ellipses, and miss patterns reveal what a mean can hide.
7. **Track opportunity counts:** Percentages without denominators are misleading.
8. **Show uncertainty:** Confidence should rise with sample size and data quality.
9. **Explain every recommendation:** Link advice to a metric, trend, and set of shots.
10. **Do not confuse precision with accuracy:** GPS and manual labels have limits; display only the resolution the data supports.

---

## Benchmark caveats

- Published handicap benchmarks come from different datasets and definitions; they should be stored as versioned references rather than hard-coded as universal truth.
- Exact category-level SG gaps between a 10 handicap and scratch were not available in the reviewed public material.
- The suggested 4% scratch-level three-putt target is directional; the sourced 10-handicap figure is about 7%.
- The 50% GIR and 240-plus-yard targets are directional endpoints, not requirements for reaching scratch.
- Before using any number in public marketing, verify it against the original Broadie, Arccos, Shot Scope, or PGA Tour source.

---

## Key sources

- [Mark Broadie interview and strokes-gained explanation](https://www.chicagogolfreport.com/mark-broadie/)
- [Broadie profile: where the 70-versus-80 scoring gap comes from](https://golf.com/travel/the-man-with-two-brains-stokes-gained-guru-mark-broadies-pioneering-analytics-have-radically-altered-the-game/)
- [Broadie academic paper on strokes gained](http://www.columbia.edu/~mnb2/broadie/Assets/strokes_gained_pga_broadie_20110408.pdf)
- [Arccos-derived driving outcomes by handicap](https://www.golfdigest.com/story/golf-digest-arccos-data-driving-stats-amateur-golfer-distance-report?itm_source=parsely-api&itm_campaign=more-from-side&itm_content=position-1)
- [Approach proximity by handicap and distance](https://www.golfmonthly.com/features/do-you-play-par-3s-better-than-the-average-amateur-golfer-compare-using-the-latest-2025-data)
- [Short misses, short-game proximity, and three-putt improvement](https://www.golfmonthly.com/features/5-statistical-improvements-that-could-slash-your-handicap-from-20-to-10)
- [Up-and-down percentage inside 50 yards](https://www.golfmonthly.com/features/scratch-vs-10-vs-20-how-often-do-amateur-golfers-get-up-and-down-from-inside-50-yards)
- [Three-putt rates by handicap](https://www.golfmonthly.com/features/data-reveals-how-many-3-putts-amateur-golfer-make-per-round)
- [Putting make rates by distance and handicap](https://www.golfmonthly.com/features/amateur-golfers-make-less-than-40-percent-of-putts-from-this-crucial-length-arccos-data-reveals-stark-putting-truths)
- [DECADE course-management principles](https://www.golfdigest.com/story/course-management-expert-scott-fawcett-tips-smarter-golf)
- [Shot Scope handicap benchmarking](https://thegolfnewsnet.com/golfnewsnetteam/2021/07/12/shot-scope-users-can-now-benchmark-their-strokes-gained-against-a-variety-of-skill-levels-123431/)
