class_name EventOutcomeData
extends Resource
## One possible result of an event choice (GDD §9c). A choice rolls one of its outcomes by weight;
## the player only sees the result after choosing. Every effect is optional.

@export var weight: float = 1.0
## What happened, shown after the choice. "{clan}" is replaced by the event's clan.
@export_multiline var text: String
## Resources gained (positive) or lost (negative, never more than the stockpile holds).
@export var resources: Dictionary[StringName, int] = {}
## Share (0..1) of each listed resource's stock that is lost.
@export var resource_loss: Dictionary[StringName, float] = {}
## Relation change with the event's clan, and with every clan.
@export var relation: int = 0
@export var relation_all: int = 0
## A new squad of this player unit (skipped when the kingdom has no room for another squad).
@export var add_unit: StringName = &""
@export var add_soldiers: int = 0
## Share (0..1) of every squad's soldiers that is lost.
@export var army_loss: float = 0.0
## Every squad below full size regains this share (0..1) of its full size.
@export var replenish: float = 0.0
## Extra land pieces added to the hand right away.
@export var extra_pieces: int = 0
## Soldiers added to (or removed from) the event clan's army.
@export var clan_strength: int = 0
## The event's clan declares war on the kingdom (when it can).
@export var declare_war: bool = false
## A general joins the kingdom, with a random star rank in this range (0 = none; GDD §8, M11d).
@export var general_min_stars: int = 0
@export var general_max_stars: int = 0
## A random item of this rarity (Item.Rarity: 0 Thường … 4 Huyền thoại, a legendary not found yet,
## else an epic one); -1 = none (GDD §8 "Trang bị", M12e).
@export var item_rarity: int = -1
@export_group("M16b")
## A random general at home leaves the kingdom (their items go back to storage).
@export var general_leaves: bool = false
## A random general or advisor at home may go over to the enemy (EventSystem.defect_chance).
@export var defection: bool = false
## Between disable_min and disable_max working production buildings stop for disable_turns turns.
@export var disable_min: int = 0
@export var disable_max: int = 0
@export var disable_turns: int = 5
## Bandits raid at the start of the next turn (if no invasion comes first).
@export var force_raid: bool = false
## Between peasant_min and peasant_max full peasant squads join (while there is room).
@export var peasant_min: int = 0
@export var peasant_max: int = 0
## The captured officer joins: a general or an advisor (half and half), stars by the event clan's
## strength (EventSystem.PRISONER_STARS).
@export var prisoner_joins: bool = false
## The choice's target_officer of the event clan is hit: wounded or killed, half and half.
@export var assassinate: bool = false
## The agent in the event clan is exposed: may be killed (Agents.kill_chance), else comes home.
@export var agent_exposed: bool = false
@export_group("M16e")
## A battle follows (EventBattles.KINDS: &"duel", &"breakout", &"surprise", &"rescue").
@export var battle: StringName = &""
## Starting morale change ("nhuệ khí tối đa", MoraleEffects) for the kingdom's army or the
## enemy's: in the next battle against the event's clan (any battle with `morale_any_battle`),
## or in every such battle for `morale_turns` turns.
@export var morale_amount: int = 0
@export var morale_enemy: bool = false
@export var morale_turns: int = 0
@export var morale_any_battle: bool = false
## The commander dies / is wounded for Generals.WOUND_TURNS turns.
@export var commander_dies: bool = false
@export var commander_wounded: bool = false
## A random detachment (EventBattles.detachment) loses this share of its soldiers.
@export var detachment_loss: float = 0.0
## The event's clan invades at the start of the next turn.
@export var force_invasion: bool = false
## The chance of a bandit raid is multiplied by this for `raid_chance_turns` turns (RaidPressure).
@export var raid_chance_factor: float = 1.0
@export var raid_chance_turns: int = 0
