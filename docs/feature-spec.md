# EDE Feature Specification

## Vision

An economic diplomacy layer for Avorion where players, alliances, and AI factions use economic tools — tariffs, trade agreements, embargoes, and enforcement — as levers of power. AI factions respond dynamically to economic pressure. Economic warfare complements or replaces military action.

---

## Core Concepts

### Diplomatic Actors

| Actor Type | Description | Power Score Source |
|---|---|---|
| **Player** | Each human player is their own faction. Solo players have full diplomacy access as "independent operators." | `numShips`, `numStations`, `money`, controlled sectors |
| **Alliance** | Player-created multi-player organization. Diplomatic actions bind all members. | `numShips`, `numStations`, `money`, controlled sectors |
| **AI Faction** | NPC empires (Corporate, Militaristic, etc.). Initiate actions reactively (provoked) or occasionally at random. | `money`, controlled sectors (territory), archetype bonus |

### Power Projection Score

A real-time score used to gate enforcement actions and calculate enforcement costs.

```
Score = (ships × W_ship) + (stations × W_station) + (money × W_money) + (sectors × W_sector) + archetype_bonus

Where:
  W_ship     = weight per ship owned
  W_station  = weight per station owned
  W_money    = weight per credit (scaled, e.g., per 100K)
  W_sector   = weight per controlled sector
  archetype_bonus = AI-only, based on faction type (Militaristic gets combat bonus, etc.)
```

- Players/Alliances: ships + stations are exact counts from API
- AI Factions: territory size (sampled via `getControllingFaction`) + money + archetype

### Enforcement Model

Two-part system:

1. **Enforcement Score Gate** — you must have a power score >= some threshold relative to the target to initiate a tariff/embargo. Prevents tiny factions from declaring embargoes on empires.
   - Tariffs: your score must be >= 30% of target's score
   - Embargoes: your score must be >= 50% of target's score
   - Sanctions (coalition): combined coalition score must be >= 50% of target's score

2. **Enforcement Cost** — ongoing credit cost per game-day cycle (3 real hours) to maintain the action. Scales with the power delta between you and the target.
   - Cost = base_cost × (target_score / your_score)
   - Stronger target = more expensive to enforce against
   - If you can't pay, enforcement lapses (tariff stops being applied, embargo becomes leaky)

### Alliance Voting

All alliance diplomatic actions require a member vote:
- Any alliance member can propose a diplomatic action
- All members receive a vote prompt (yes/no)
- Vote window: configurable (default: 1 game-day / 3 real hours)
- Simple majority passes; tie declines
- Each member gets exactly one vote
- Alliance leader's vote does NOT count extra
- Results announced to all members via chat message

---

## Feature List

### F1: Power Projection Score System
Calculate and persist a real-time power score for all diplomatic actors.

- [ ] **F1.1** Score calculation engine (pure logic module in `lib/`)
  - Ships, stations, money, territory as inputs
  - Configurable weights (tunable constants)
  - AI archetype bonus table
- [ ] **F1.2** Territory scanner — sample `getControllingFaction` to estimate sector control per faction
  - Scan on a timer (not every tick — expensive)
  - Cache results with TTL
- [ ] **F1.3** Score persistence — store via `setValue` on Galaxy, refresh periodically
- [ ] **F1.4** Score comparison API — functions to check "can Faction A enforce against Faction B?"

### F2: Tariff System
Sector-based import tax on all goods when selling to a tariffed faction's stations.

- [ ] **F2.1** Tariff data model — store bilateral tariff state (who imposed, rate, enforcement status)
- [ ] **F2.2** Tariff declaration — actor declares tariff on target (enforcement score gate check)
- [ ] **F2.3** Tariff enforcement cost — ongoing credit deduction per game-day cycle
- [ ] **F2.4** Trade hook — intercept `onBought`/`onSold` on stations, apply surcharge based on buyer/seller faction pairs and active tariffs
- [ ] **F2.5** Tariff revenue — surcharge credits go to the imposing faction (they profit from the tariff)
- [ ] **F2.6** Tariff removal — voluntary removal or automatic lapse if enforcement cost can't be paid
- [ ] **F2.7** AI reaction — AI faction retaliates with counter-tariff if tariffed (based on archetype aggression)

### F3: Trade Agreement System
Bilateral or asymmetric discount agreements between two actors.

- [ ] **F3.1** Trade agreement data model — two-sided discount rates, proposer/acceptor
- [ ] **F3.2** Proposal flow — one actor proposes, the other accepts/declines
  - AI acceptance based on: relation level, archetype (Corporate more likely), existing conflicts
- [ ] **F3.3** Trade hook — apply discount on transactions between agreement partners
- [ ] **F3.4** Agreement termination — either side can cancel; tariffs/embargoes automatically cancel conflicting agreements
- [ ] **F3.5** Relation improvement — active trade agreements slowly improve faction relations over time

### F4: Embargo System
Full trade block — target faction's ships/alliance ships cannot sell to the embargoing faction's stations.

- [ ] **F4.1** Embargo data model — who imposed, enforcement status, start time
- [ ] **F4.2** Embargo declaration — enforcement score gate (50% threshold), higher cost than tariffs
- [ ] **F4.3** Trade block hook — reject transactions between embargoed faction pairs
- [ ] **F4.4** Embargo enforcement cost — higher than tariffs, scales with power delta
- [ ] **F4.5** Embargo lapse — automatic if enforcement cost can't be paid
- [ ] **F4.6** AI reaction — AI factions treat embargo as hostile act (significant relation drop), may declare war
- [ ] **F4.7** Smuggling opportunity — if enforcement is weak (cost not fully paid), transactions have a % chance of going through anyway. Risk/reward for traders.

### F5: Sanctions (Coalition Embargo)
Multiple actors coordinate to collectively embargo a target.

- [ ] **F5.1** Sanctions proposal — one actor proposes, invites others to join
- [ ] **F5.2** Coalition formation — each invited actor votes to join/decline
- [ ] **F5.3** Combined enforcement score — sum of all coalition members' scores for the gate check
- [ ] **F5.4** Shared enforcement cost — split proportionally among coalition members by score
- [ ] **F5.5** Sanctions apply trade block from ALL coalition members to the target
- [ ] **F5.6** Coalition dissolution — any member can withdraw; sanctions weaken proportionally

### F6: Persona Non Grata
Target an individual player (not a whole faction) with tariffs or trade blocks.

- [ ] **F6.1** PNG declaration — an actor declares a specific player persona non grata
- [ ] **F6.2** PNG effects — tariff surcharge or full trade block applied to that specific player at all declaring faction's stations
- [ ] **F6.3** PNG does NOT affect the player's alliance mates (unless the whole alliance is tariffed separately)
- [ ] **F6.4** Lower enforcement threshold than full faction tariffs (targeting one player is easier)

### F7: Alliance Voting System
Democratic governance for alliance diplomatic actions.

- [ ] **F7.1** Vote initiation — any alliance member can propose a diplomatic action. The proposer's vote is automatically "yes" (they do not vote separately).
- [ ] **F7.2** Vote prompt — all other members receive a notification with the proposal details
- [ ] **F7.3** Vote window — fixed short window (default 15 real minutes). Non-responses default to "yes" (opt-out model — oppose it or it passes).
- [ ] **F7.4** Vote tallying — simple majority passes, tie declines. Proposer counts as "yes". Non-voters count as "yes".
- [ ] **F7.5** Early close — if enough votes are in to determine the outcome before the window expires, close immediately
- [ ] **F7.6** Vote result notification — outcome announced to all alliance members via chat
- [ ] **F7.7** Auto-execute — if vote passes, the diplomatic action takes effect immediately
- [ ] **F7.8** Vote history — record of past votes accessible in the diplomacy panel

### F8: AI Faction Behavior
AI factions react to and occasionally initiate economic actions.

- [ ] **F8.1** Reactive behavior — AI retaliates when tariffed/embargoed based on archetype:
  - Corporate: counter-tariff first, escalate slowly
  - Militaristic: skip to embargo or war quickly
  - Independent: break off trade agreements, go neutral
  - Religious/Traditional: hold grudges longer, slow to forgive
- [ ] **F8.2** Proactive behavior — occasional random tariff/agreement initiation:
  - AI factions randomly propose trade agreements to factions they like
  - AI factions randomly impose tariffs on factions they dislike
  - Frequency: low (every few game-days, small chance per cycle)
- [ ] **F8.3** AI-vs-AI — random economic conflicts between AI factions:
  - Cursory implementation: dice roll per game-day, small chance of tariff/embargo between AI factions that have low relations
  - No deep strategic planning — just flavor events that make the galaxy feel alive
- [ ] **F8.4** AI response to player power — if player's power score grows too large relative to nearby AI factions, they become economically hostile (tariffs, breaking agreements)

### F9: Diplomacy Panel (UI)
Dedicated panel accessible anywhere via hotkey or menu button.

- [ ] **F9.1** Panel layout — tabbed interface matching Avorion's UI style:
  - **Overview tab**: list of all known factions with diplomatic status, your power score, their estimated power score
  - **Agreements tab**: active trade agreements, tariffs imposed by you, tariffs imposed on you
  - **Actions tab**: declare tariff, propose trade agreement, declare embargo, propose sanctions, declare PNG
  - **Voting tab** (alliance members only): active vote proposals, vote history
  - **Intelligence tab**: economic overview (who trades with whom, major trade routes — stretch goal)
- [ ] **F9.2** Access gate — if player has no alliance, panel shows "Acting as independent operator" (full access, just informational label)
- [ ] **F9.3** Faction detail view — click any faction to see: power score breakdown, active diplomatic states, relation level, archetype, trade volume estimate
- [ ] **F9.4** Action confirmation — all diplomatic actions show enforcement cost estimate and power score comparison before confirming
- [ ] **F9.5** Notification feed — recent diplomatic events ("Faction X imposed tariffs on you", "Trade agreement with Faction Y expired", "Embargo enforcement lapsed — insufficient funds")

### F10: Persistence
Full save/load of all mod state.

- [ ] **F10.1** All diplomatic states persisted via `Galaxy():setValue()` with JSON serialization
- [ ] **F10.2** Power score cache persisted and refreshed on load
- [ ] **F10.3** Active votes persisted (resume after server restart)
- [ ] **F10.4** Enforcement cost timers persisted
- [ ] **F10.5** Backward-compatible — new fields always have defaults so old saves load cleanly

---

## Implementation Phases

### Phase 1: Foundation (V0.1)
Get the core loop working with the simplest possible vertical slice.
- F1 (Power Score) — full implementation
- F2 (Tariffs) — full implementation
- F3 (Trade Agreements) — full implementation
- F9 (Diplomacy Panel) — minimal: overview + actions tabs only
- F10 (Persistence) — full implementation
- F8.1 (AI Reactive) — tariff retaliation only

### Phase 2: Escalation (V0.2)
Add the aggressive economic tools and alliance governance.
- F4 (Embargoes) — full implementation
- F7 (Alliance Voting) — full implementation
- F8.1 (AI Reactive) — full archetype responses
- F8.2 (AI Proactive) — random agreements/tariffs
- F9 (Diplomacy Panel) — add voting tab, notifications

### Phase 3: Coalition & Depth (V0.3)
Add multi-faction coordination, persona non grata, and AI-vs-AI.
- F5 (Sanctions) — full implementation
- F6 (Persona Non Grata) — full implementation
- F8.3 (AI-vs-AI) — cursory random economic conflicts
- F8.4 (AI response to player power)
- F9 (Diplomacy Panel) — full intelligence tab, faction detail views

---

## Constants (Tunable)

| Constant | Default | Description |
|---|---|---|
| `SCORE_WEIGHT_SHIP` | 10 | Power score points per ship |
| `SCORE_WEIGHT_STATION` | 25 | Power score points per station |
| `SCORE_WEIGHT_MONEY` | 1 per 100K | Power score points per 100K credits |
| `SCORE_WEIGHT_SECTOR` | 15 | Power score points per controlled sector |
| `TARIFF_MIN_SCORE_RATIO` | 0.30 | Min your_score / target_score to declare tariff |
| `EMBARGO_MIN_SCORE_RATIO` | 0.50 | Min score ratio to declare embargo |
| `TARIFF_BASE_COST` | 10,000 | Base credits per game-day to enforce a tariff |
| `EMBARGO_BASE_COST` | 25,000 | Base credits per game-day to enforce an embargo |
| `TARIFF_DEFAULT_RATE` | 0.15 | Default tariff rate (15%) |
| `TARIFF_MAX_RATE` | 0.50 | Maximum tariff rate (50%) |
| `TRADE_AGREEMENT_DEFAULT_DISCOUNT` | 0.10 | Default discount (10%) |
| `TRADE_AGREEMENT_MAX_DISCOUNT` | 0.30 | Maximum discount (30%) |
| `VOTE_WINDOW_SECONDS` | 900 | Vote duration (15 real minutes) |
| `SCORE_REFRESH_INTERVAL` | 3,600 | Seconds between power score recalculations |
| `AI_RETALIATION_CHANCE` | 0.80 | Chance AI retaliates to tariff (per cycle) |
| `AI_RANDOM_ACTION_CHANCE` | 0.05 | Chance AI initiates random economic action (per game-day) |
| `ENFORCEMENT_LAPSE_GRACE` | 1 | Game-days of grace before enforcement lapses on missed payment |
| `SMUGGLING_BASE_CHANCE` | 0.20 | Base chance of trade going through during weak embargo |

---

## Out of Scope (Explicitly Not Building)

- Good-specific tariffs (all goods tariffed equally)
- Conditional trade agreements ("don't trade with Faction C")
- Custom goods / contraband system
- Trade route visualization on galaxy map
- New faction creation by players
- Modification of vanilla UI panels
- Changes to vanilla combat mechanics
- Alliance creation/management (using vanilla system)
