class_name AttackData
extends Resource

## Data-only definition for one base ground attack.
## Frame data/reaction values are provisional playtest baselines unless noted.

const TICKS_PER_SECOND: int = 60

enum AttackKind {
	LIGHT,
	HEAVY,
	SPECIAL,
}

enum HitLevel {
	UNSPECIFIED,
	MID,
	HIGH,
	LOW,
}

@export_group("Identity")
@export var attack_id: StringName = &""
@export var display_name: String = ""
@export var attack_kind: AttackKind = AttackKind.LIGHT
@export var input_bit: int = InputBits.LIGHT
@export var hit_level: HitLevel = HitLevel.UNSPECIFIED

@export_group("Base attack data — provisional playtest baseline")
@export_range(0, 9999, 1) var base_damage: int = 0
@export_range(1, 999, 1) var startup_ticks: int = 1
@export_range(1, 999, 1) var active_ticks: int = 1
@export_range(0, 999, 1) var recovery_ticks: int = 0
@export_range(0.0, 9999.0, 0.1) var base_knockback_px: float = 0.0
@export var balance_status: String = "PROVISIONAL — PLAYTEST BASELINE — OWNER REVIEW REQUIRED"

@export_group("Reaction data — provisional unless otherwise specified")
@export_range(-1, 999, 1) var hitstun_ticks: int = -1
@export_range(-1, 999, 1) var blockstun_ticks: int = -1
@export_range(-1, 999, 1) var down_duration_ticks: int = -1
@export_range(-1, 999, 1) var hitstop_ticks: int = -1

@export_group("Costs and combo")
## Special cost is expressed in bars, not legacy 0–100 points.
@export_range(0, 5, 1) var special_cost_bars: int = 0
## Zero means no per-attack combo limit is defined here.
@export_range(0, 99, 1) var combo_limit: int = 0


func get_active_start_tick() -> int:
	## Attack elapsed ticks are zero-based. Startup=5 means active starts at elapsed tick 5.
	return startup_ticks


func get_active_end_tick_exclusive() -> int:
	return startup_ticks + active_ticks


func get_total_ticks() -> int:
	return startup_ticks + active_ticks + recovery_ticks


func is_startup_tick(elapsed_tick: int) -> bool:
	return elapsed_tick >= 0 and elapsed_tick < startup_ticks


func is_active_tick(elapsed_tick: int) -> bool:
	return elapsed_tick >= get_active_start_tick() and elapsed_tick < get_active_end_tick_exclusive()


func is_recovery_tick(elapsed_tick: int) -> bool:
	return elapsed_tick >= get_active_end_tick_exclusive() and elapsed_tick < get_total_ticks()


func is_recovery_complete(elapsed_tick: int) -> bool:
	return elapsed_tick >= get_total_ticks()


func validate() -> PackedStringArray:
	var errors := PackedStringArray()

	if attack_id == &"":
		errors.append("attack_id must not be empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name must not be empty")
	if input_bit < 0 or input_bit >= InputBits.COUNT:
		errors.append("input_bit is outside the 11-bit logical input schema")
	if base_damage < 0:
		errors.append("base_damage must be >= 0")
	if startup_ticks < 1:
		errors.append("startup_ticks must be >= 1")
	if active_ticks < 1:
		errors.append("active_ticks must be >= 1")
	if recovery_ticks < 0:
		errors.append("recovery_ticks must be >= 0")
	if base_knockback_px < 0.0:
		errors.append("base_knockback_px must be >= 0")
	if hitstun_ticks < -1 or blockstun_ticks < -1 or down_duration_ticks < -1 or hitstop_ticks < -1:
		errors.append("reaction ticks must be -1 (unspecified) or >= 0")
	if special_cost_bars < 0 or special_cost_bars > 5:
		errors.append("special_cost_bars must be between 0 and 5")
	if combo_limit < 0:
		errors.append("combo_limit must be >= 0")

	match attack_kind:
		AttackKind.LIGHT:
			if input_bit != InputBits.LIGHT:
				errors.append("Light attack must map to InputBits.LIGHT")
			if special_cost_bars != 0:
				errors.append("Light attack cannot have a Special bar cost")
		AttackKind.HEAVY:
			if input_bit != InputBits.HEAVY:
				errors.append("Heavy attack must map to InputBits.HEAVY")
			if special_cost_bars != 0:
				errors.append("Heavy attack cannot have a Special bar cost")
		AttackKind.SPECIAL:
			if input_bit != InputBits.SPECIAL:
				errors.append("Special attack must map to InputBits.SPECIAL")
			if special_cost_bars != 1:
				errors.append("MVP Special cost must be expressed as 1 bar")

	return errors


func is_valid() -> bool:
	return validate().is_empty()
