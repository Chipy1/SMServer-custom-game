TRASHBOT_PATTERNS = TRASHBOT_PATTERNS or {}
TRASHBOT_HP_THRESHOLDS = TRASHBOT_HP_THRESHOLDS or {}
TRASHBOT_BULLET_HELL_SETTINGS = TRASHBOT_BULLET_HELL_SETTINGS or {}
TRASHBOT_STATS = TRASHBOT_STATS or {}
TRASHBOT_ARM = {
	right = 1,
	left = 2
}
TRASHBOT_ROTATION_SPEED = 45 -- degrees per second
TRASHBOT_EXPLOSION_RADIUS = 30.0

dofile "$SURVIVAL_DATA/Scripts/game/trashbot/Fight1Patterns.lua"
dofile "$SURVIVAL_DATA/Scripts/game/trashbot/Fight2Patterns.lua"


-- Sequence requirements: type (TrashbotAttack), count (int)
-- Sequence optionals: nextAttackWaitTime (float), clockwise (bool), preset (string), repeatable (bool), forceArm (Arm)
-- nextAttackWaitTime controls the time before the next attacks is activated.
-- clockwise will control the rotational direction of certain attacks.
-- preset is only used for trash balls, listed presets are in TrashBallState.lua.
-- if repeatable is false that attack will not be used again when we loop the sequence during the loop duration.
-- forceArm will force the attack to be used by the given arm. By default the right arm is the first choice.
-- color will change the color of following shockwaves, the alternatives are "green" and "purple".
-- multiplayerOnly will make the the attack only activate if there are more than one player in the fight
-- waveAmount will control the number of shockwaves spawned for a single jump, resets automatically between jumps.
-- eyeOpen will control if the trashbot can be damaged during the attack or not by opening/closing the eye.