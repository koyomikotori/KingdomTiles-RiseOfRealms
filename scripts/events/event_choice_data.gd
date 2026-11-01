class_name EventChoiceData
extends Resource
## One answer to an event (GDD §9c): its cost is always shown (and must be affordable); what it
## leads to is only hinted at until it is chosen.

@export var text: String
## Shown under the choice instead of the exact result ("They may remember this…").
@export var hint: String
## Paid up front when chosen.
@export var cost: Dictionary[StringName, int] = {}
## One is rolled by weight. Empty = nothing else happens.
@export var outcomes: Array[EventOutcomeData] = []
@export_group("Chance (M16b)")
## Below 0: the outcomes are rolled by weight. Otherwise the first outcome happens with this
## chance plus the bonuses below (EventSystem.choice_chance, shown to the player) and the second
## one otherwise.
@export var success_chance: float = -1.0
## Per star of the advisor in the Ngoại giao post, of the agent in the event clan, per police level.
@export var chance_per_envoy_star: float = 0.0
@export var chance_per_agent_star: float = 0.0
@export var chance_per_police_level: float = 0.0
@export_group("Requirements (M16b)")
## Needs room for one more general or advisor.
@export var needs_officer_slot: bool = false
## &"general" / &"advisor": the event clan must field this officer (the assassination target).
@export var target_officer: StringName = &""
@export_group("Requirements (M16e)")
## The commander must be at home and able to fight.
@export var needs_commander: bool = false
## Squads at home (not on an expedition) needed.
@export var min_squads_home: int = 0
## The player picks one of the generals at home, ready to fight, for the battle (EventWindow).
@export var pick_general: bool = false
