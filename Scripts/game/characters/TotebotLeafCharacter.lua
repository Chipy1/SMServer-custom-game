dofile "$SURVIVAL_DATA/Scripts/game/characters/BaseEnemyCharacter.lua"
dofile "$SURVIVAL_DATA/Scripts/game/characters/TotebotCharacter.lua"
TotebotLeafCharacter = class( TotebotCharacter )

local animationSets = {
	alert = "$SURVIVAL_DATA/Character/Char_Totebot/char_totebot_alert.rend",
	roaming = "$SURVIVAL_DATA/Character/Char_Totebot/char_totebot_roaming.rend"
}

sm.character.preloadRenderables( { animationSets.alert, animationSets.roaming } )

function TotebotLeafCharacter.sv_e_setLeafState( self, leafActive )
	self.network:setClientData( { leafActive = leafActive }, 1  )
end

function TotebotLeafCharacter.client_onClientDataUpdate( self, data, channel )
	self.cl.leafActive = data.leafActive
	self:cl_updateLeaf()
end

function TotebotLeafCharacter.cl_updateLeaf( self )
	if self.cl.leafActive then
		if sm.exists( self.cl.effects.leaf ) and not self.cl.effects.leaf:isPlaying() then
			self.cl.effects.leaf:start()
		end
	else
		if sm.exists( self.cl.effects.leaf ) and self.cl.effects.leaf:isPlaying() then
			self.cl.effects.leaf:stopImmediate()
			sm.effect.playHostedEffect( "Totebot - LeafbushDestruct", self.character, "jnt_head" )
		end
	end
end


function TotebotLeafCharacter.client_onGraphicsLoaded( self )
	self.character:addRenderable( animationSets[self.cl.currentAnimationSet] )
	self:cl_initGraphics()
	self:cl_initAnimationSwitch()
	self.character:setGlowMultiplier( 1 )
	self.graphicsLoaded = true

	self.cl.effects = {}
	self.cl.effects.alerted = sm.effect.createEffect( "ToteBot - Alerted", self.character, "jnt_head" )
	self.cl.effects.attack = sm.effect.createEffect( "ToteBot - Attack", self.character )
	self.cl.effects.leaf = sm.effect.createEffect( "Totebot - Leafbush", self.character, "jnt_head" )
	self.cl.effects.launch = sm.effect.createEffect( "ToteBot - Attack", self.character )
	self.cl.effects.inAir = sm.effect.createEffect( "ToteBot - Attack", self.character )
	self:cl_updateLeaf()
end

function TotebotLeafCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false

	if self.cl.effects.alerted then
		self.cl.effects.alerted:destroy()
		self.cl.effects.alerted = nil
	end
	if self.cl.effects.attack then
		self.cl.effects.attack:destroy()
		self.cl.effects.attack = nil
	end
	if self.cl.effects.leaf then
		self.cl.effects.leaf:destroy()
		self.cl.effects.leaf = nil
	end
end