dofile "$SURVIVAL_DATA/Scripts/game/characters/TotebotCharacter.lua"

LootbotCharacter = class( TotebotCharacter )

local alertRenderableTp = "$SURVIVAL_DATA/Character/Char_Totebot/char_totebot_alert.rend"
local roamingRenderableTp = "$SURVIVAL_DATA/Character/Char_Totebot/char_totebot_roaming.rend"
sm.character.preloadRenderables( { alertRenderableTp, roamingRenderableTp } )

local animationSets = {
	alert = "$SURVIVAL_DATA/Character/Char_Totebot/char_totebot_alert.rend",
	roaming = "$SURVIVAL_DATA/Character/Char_Totebot/char_totebot_roaming.rend"
}

function LootbotCharacter.client_onGraphicsLoaded( self )

	self.character:addRenderable( animationSets[self.cl.currentAnimationSet] )
	self:cl_initGraphics()
	self:cl_initAnimationSwitch()
	self.character:setGlowMultiplier( 1 )
	self.graphicsLoaded = true

	self.cl.effects = {}
	self.cl.effects.trail = sm.effect.createEffect( "Lootbot - Trail", self.character, "jnt_head" )
	self.cl.effects.trail:start()
end

function LootbotCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false

	if self.cl.effects.trail then
		self.cl.effects.trail:destroy()
		self.cl.effects.trail = nil
	end
end

function LootbotCharacter.cl_handleEvent( self, event )
	if not self.animationsLoaded then
		return
	end

	if sm.exists( self.character ) then

		if event == "death" then
			SpawnDebris( self.character, "jnt_spine1", "Robotparts - LootbotBody" )
			SpawnDebris( self.character, "jnt_01_upperleg", "Robotparts - LootbotLeg" )
			SpawnDebris( self.character, "jnt_02_upperleg", "Robotparts - LootbotLeg" )
			SpawnDebris( self.character, "jnt_03_upperleg", "Robotparts - LootbotLeg" )
			SpawnDebris( self.character, "jnt_04_upperleg", "Robotparts - LootbotLeg" )
			SpawnDebris( self.character, "jnt_05_upperleg", "Robotparts - LootbotLeg" )
			SpawnDebris( self.character, "jnt_06_upperleg", "Robotparts - LootbotLeg" )

			SpawnDebris( self.character, "jnt_head", "Lootbot - DestroyedParts" )
			SpawnDebris( self.character, "jnt_head", "Lootbot - Lootcratedestroy" )
		else
			self.cl.currentAnimation = ""
		end
	end
end
