class_name CombatResolutionController
extends RefCounted

## M9-A: resolves an already-confirmed unguarded hit.
## Hitbox owns overlap detection and per-attack target deduplication.
## This controller owns damage and reaction selection only.
## Knockback and Guard/Gauge are intentionally handled by separate systems.

signal hit_resolved(
    attacker_fighter_id: StringName,
    target_fighter_id: StringName,
    attack_instance_id: int,
    damage_applied: int,
    reaction_kind: int
)

enum ResolveResult {
    APPLIED,
    INVALID_ATTACKER,
    INVALID_ATTACK_INSTANCE,
    INVALID_ATTACK_DATA,
    INVALID_HURTBOX,
    SELF_HIT,
    INVALID_TARGET,
    INVALID_HEALTH_COMPONENT,
    TARGET_DEFEATED,
    NO_DAMAGE,
}

enum ReactionApplied {
    NONE,
    HITSTUN,
    DOWN,
}


func resolve_hit(
    attacker: Node,
    attacker_fighter_id: StringName,
    attack_instance_id: int,
    attack_data: Resource,
    hurtbox: Area2D
) -> int:
    if not is_instance_valid(attacker):
        return ResolveResult.INVALID_ATTACKER

    if StringName(attacker.name) != attacker_fighter_id or attacker_fighter_id == &"":
        return ResolveResult.INVALID_ATTACKER

    if attack_instance_id <= 0:
        return ResolveResult.INVALID_ATTACK_INSTANCE

    if attack_data == null \
            or not attack_data.has_method("is_valid") \
            or not bool(attack_data.call("is_valid")):
        return ResolveResult.INVALID_ATTACK_DATA

    if not is_instance_valid(hurtbox) \
            or not hurtbox.has_method("get_owner_fighter_id"):
        return ResolveResult.INVALID_HURTBOX

    var target_fighter_id: StringName = StringName(
        hurtbox.call("get_owner_fighter_id")
    )

    if target_fighter_id == &"":
        return ResolveResult.INVALID_HURTBOX

    if target_fighter_id == attacker_fighter_id:
        return ResolveResult.SELF_HIT

    # M6 creates HurtboxComponent as a direct child of FighterController.
    var target: Node = hurtbox.get_parent()
    if not is_instance_valid(target) \
            or StringName(target.name) != target_fighter_id \
            or not target.has_method("get_health_component"):
        return ResolveResult.INVALID_TARGET

    var health: Node = target.call("get_health_component") as Node
    if not is_instance_valid(health) \
            or not health.has_method("apply_damage") \
            or not health.has_method("is_alive"):
        return ResolveResult.INVALID_HEALTH_COMPONENT

    if not bool(health.call("is_alive")):
        return ResolveResult.TARGET_DEFEATED

    var base_damage: int = int(attack_data.get("base_damage"))
    if base_damage <= 0:
        return ResolveResult.NO_DAMAGE

    var damage_applied: int = int(health.call("apply_damage", base_damage))
    if damage_applied <= 0:
        return ResolveResult.TARGET_DEFEATED

    var reaction_kind: int = ReactionApplied.NONE

    # A lethal hit ends the fighter; do not start a new reaction timer.
    if bool(health.call("is_alive")):
        var down_ticks: int = int(attack_data.get("down_duration_ticks"))
        var hitstun_ticks: int = int(attack_data.get("hitstun_ticks"))

        if down_ticks > 0 and target.has_method("apply_down"):
            target.call("apply_down", down_ticks)
            reaction_kind = ReactionApplied.DOWN
        elif hitstun_ticks > 0 and target.has_method("apply_hitstun"):
            target.call("apply_hitstun", hitstun_ticks)
            reaction_kind = ReactionApplied.HITSTUN

    hit_resolved.emit(
        attacker_fighter_id,
        target_fighter_id,
        attack_instance_id,
        damage_applied,
        reaction_kind
    )

    return ResolveResult.APPLIED
