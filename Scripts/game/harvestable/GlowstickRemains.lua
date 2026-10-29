-- GlowstickRemains.lua --
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"

GlowstickRemains = class( nil )

function GlowstickRemains.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.destroyTick = sm.game.getCurrentTick() + 40 * 720 -- 12m
		self.storage:save( self.sv.saved )
	else
		-- changed from self.sv.saved.ticksLeftInWorld and self.sv.saved.lastTickUpdate
		self.sv.saved.destroyTick = self.sv.saved.destroyTick or sm.game.getCurrentTick() + 40 * 720 -- 12m
	end
end

function GlowstickRemains.server_onReceiveUpdate( self )
	-- Destroy the remains if it has existed for too long
	if sm.game.getCurrentTick() >= self.sv.saved.destroyTick then
		if not self.sv.removed then
			self.sv.removed = true
			sm.harvestable.destroy( self.harvestable )
		end
	end
end

function GlowstickRemains.server_canErase( self ) return true end
function GlowstickRemains.client_canErase( self ) return true end

function GlowstickRemains.server_onRemoved( self, player )
	if not self.sv.removed then
		self.sv.removed = true
		sm.harvestable.destroy( self.harvestable )
		sm.effect.playEffect( "GlowstickProjectile - Bounce",  self.harvestable.worldPosition, nil, self.harvestable.worldRotation )
	end
end

function GlowstickRemains.client_onCreate( self )
	self.cl = {}
	self.cl.glowEffect = sm.effect.createEffect( "GlowstickProjectile - Hit" )
	self.cl.glowEffect:setPosition( self.harvestable.worldPosition )
	self.cl.glowEffect:setRotation( self.harvestable.worldRotation )
	self.cl.glowEffect:start()
end

function GlowstickRemains.client_onDestroy( self )
	self.cl.glowEffect:stop()
	self.cl.glowEffect:destroy()
end

function GlowstickRemains.client_onInteract( self, state ) end

function GlowstickRemains.client_canInteract( self )
	if not sm.localPlayer.secondaryInteractBusy() then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Attack", true ), "#{INTERACTION_DESTROY}" )
	end
	return false
end
