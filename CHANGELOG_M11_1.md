# M11.1 Change Log

- Replaced the fixed three-card catalog design with an explicit extensible CardDatabase.
- Added seven Phase 1 CardData resources while keeping only three MVP cards unlocked by default.
- Added CardCollection unlock records with default/tournament/NPC/achievement sources and save-data import/export boundaries.
- Added MVP and Phase 1 CardDeckRules profiles plus duplicate policy that remains unresolved until owner selection.
- Added CardDeckBuilder validation for deck size, unknown cards, locked cards and duplicate policy.
- Reworked CardController to draw a hand of up to five cards from a larger deck and redraw after the configured shuffle delay.
- Generalized effect data to support multiple effects per card, effect IDs, triggers and parameters.
- Preserved a separate CardGauge (max 5, starts 5, +1 / 240 ticks) and compatibility accessors for the three MVP combat modifiers.
- Added M11.1 test suite for data, collection, deck construction, hand limit/cycling, gauge, effect refresh and input validation.
- No FighterController, combat resolver, scene, project settings, Input Map or M1–M10 files are changed by this bundle.
- Conditional effects are emitted as requests and only enter the timed-effect table after M12 confirms the trigger via `apply_timed_effect`; this prevents HP/evade-gated bonuses from activating prematurely.
- Empty-hand snapshots are emitted immediately when the last card is used; tick state is committed only after CardGauge accepts the same tick.
- Added a capped `CardGaugeComponent.add_gauge()` API for effects that restore Card Gauge.
