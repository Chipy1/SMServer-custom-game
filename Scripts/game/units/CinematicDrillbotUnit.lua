dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"

CinematicDrillbotUnit = class( nil )

function CinematicDrillbotUnit.server_onCreate( self )
	sm.message.subscribe( MESSAGE_TYPES.EFFECT_EVENTS.DrillbotDrop, "sv_m_drillbotDrop" )
end

function CinematicDrillbotUnit.sv_m_drillbotDrop( self )
	-- Sync animation state to all clients
	sm.event.sendToCharacter( self.unit.character, "sv_e_setAnimationState", {
		currentEvent = MESSAGE_TYPES.EFFECT_EVENTS.DrillbotDrop,
		startTick = sm.game.getCurrentTick()
	})
end