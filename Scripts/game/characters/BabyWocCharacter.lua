dofile "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua"

BabyWocCharacter = class( nil )

local DefaultColor = sm.color.new( 0.94, 0.58, 0.50 )
local GlowColor = sm.color.new( 1.3, 0.8, 0.68 )

local BabyWocGui = {}
BabyWocGui.json = DeepCopy( dofile( "$SURVIVAL_DATA/Gui/JsonGuis/Babywoc.gui" ) )
BabyWocGui.MainPanel = FindWidget( BabyWocGui.json, "MainPanel" )
ReplaceSubLayouts( BabyWocGui.MainPanel )

local BaguetteHolder = FindWidget( BabyWocGui.json, "BaguetteHolder" )
local GlowstickHolder = FindWidget( BabyWocGui.json, "GlowstickHolder" )
local InventoryBox = FindWidget( BabyWocGui.json, "InventoryBox" )
local BaguetteBox = FindWidget( BaguetteHolder, "BaguetteBox" )
local GlowstickBox = FindWidget( GlowstickHolder, "GlowstickBox" )

function BabyWocCharacter.server_onCreate( self )
	if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
		self.character:setImmovable( true )
	end
	local followerData = BabyWocManager.Sv_GetFollowerData()
	local glowActive = followerData and followerData.glowstickContainer and not followerData.glowstickContainer:isEmpty()
	local baguetteActive = followerData and followerData.baguetteContainer and not followerData.baguetteContainer:isEmpty()
	self:sv_e_updateState( { glowstickState = glowActive, baguetteState = baguetteActive } )
end

function BabyWocCharacter.sv_e_updateState( self, params )
	self.character.color = params.glowstickState and GlowColor or DefaultColor
	self.network:setClientData( params )
end

function BabyWocCharacter.client_onCreate( self )
	self.cl = {}
	self.cl.gui = nil
	self.cl.animations = {}
	self.cl.glowActive = false
	self.cl.baguetteActive = false
end

function BabyWocCharacter.client_onDestroy( self )
	if self.cl.gui and sm.exists( self.cl.gui ) and self.cl.gui:isActive() then
        self.cl.gui:close()
        self.cl.gui = nil
    end
end

function BabyWocCharacter.client_onRefresh( self ) end

function BabyWocCharacter.client_canInteract( self )
	local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
	sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_INTERACT}" )
	return true
end

function BabyWocCharacter.client_onInteract( self, character, state )
	if LogEntryManager.Cl_HasLog( LOGS.log_babywoc ) then
		if state then
			if self.cl.gui then
				if sm.exists( self.cl.gui ) and self.cl.gui:isActive() then
					self.cl.gui:close()
				end
				self.cl.gui = nil
			end
			local followerData = BabyWocManager.Cl_GetFollowerData()
			if followerData and BabyWocGui and InventoryBox and BaguetteBox and GlowstickBox then
				if self.cl.gui == nil then
					self.cl.gui = sm.jsonGui.createGui( { isInteractive = true, bNeedsCursor = true, hidesHotbar = true } )
				end
				local playerInventoryId = sm.localPlayer.getInventory().id
				local baguetteContainerId
				local glowstickContainerId
				if followerData.baguetteContainer then
					baguetteContainerId = followerData.baguetteContainer.id
				end
				if followerData.glowstickContainer then
					glowstickContainerId = followerData.glowstickContainer.id
				end

				InventoryBox.ContainerData.ContainerId = playerInventoryId
				InventoryBox.ContainerData.DropContainerIds = { baguetteContainerId, glowstickContainerId }
				BaguetteBox.ContainerData.ContainerId = baguetteContainerId
				BaguetteBox.ContainerData.DropContainerIds = { playerInventoryId }
				GlowstickBox.ContainerData.ContainerId = glowstickContainerId
				GlowstickBox.ContainerData.DropContainerIds = { playerInventoryId }
				BabyWocGui.json.Hotbar.DropContainerIds = { baguetteContainerId, glowstickContainerId }
				self.cl.gui:render( BabyWocGui.json )
			end
		end
	else
		self.network:sendToServer( "sv_n_rescueBabywoc" )
	end
end

function BabyWocCharacter.sv_n_rescueBabywoc( self, _, player )
	LogEntryManager.Sv_AddLog( LOGS.log_babywoc )
	BabyWocManager.Sv_RegisterFollower( self.character:getUnit(), player )
	sm.achievement.seti("2c8af9a4-599e-44cb-bfd2-cff8f9c636e0",1 )
	self.character:setImmovable( false )
	self.network:sendToClients( "cl_n_rescuedBabywoc" )
end

function BabyWocCharacter.cl_n_rescuedBabywoc( self, _, player )
	if self.cl.cryEffect then
		self.cl.cryEffect:stop()
	end
end

function BabyWocCharacter.cl_onClose( self )
	self.cl.gui = nil
end

function BabyWocCharacter.cl_initAnimation( self, name, args )
	self.cl.animations[name] = {
		info = self.character:getAnimationInfo( name ),
		time = 0,
		weight = 0
	}

	if type( args ) == "table" then
		for key, value in pairs( args ) do
			self.cl.animations[name][key] = value
		end
	end
end

function BabyWocCharacter.client_onGraphicsLoaded( self )

	-- Third person animations
	self:cl_initAnimation( "idlespecial01" )
	self:cl_initAnimation( "idlespecial02" )
	self:cl_initAnimation( "cow_eat_grass" )
	self:cl_initAnimation( "hang_loop", { active = false } )
	self:cl_initAnimation( "hang_getup", { active = false } )

	self.animationsLoaded = true

	self.blendSpeed = 5.0
	self.blendTime = 0.2

	self.currentAnimation = ""

	self.character:setMovementEffects( "$SURVIVAL_DATA/Character/Char_babywoc/movement_effects.json" )
	self.character:setGlowMultiplier( self.cl.glowActive and 1 or 0 )

	self.cl.glowEffect = sm.effect.createEffect( "Babywoc - Glow", self.character, "jnt_head" )
	self.cl.glowstickEffect = sm.effect.createEffect( "Babywoc - Glowstick", self.character, "jnt_nose" )
	if self.cl.glowActive then
		self.cl.glowEffect:start()
		self.cl.glowstickEffect:start()
	end

	self.cl.baguetteEffect = sm.effect.createEffect( "Babywoc - Baguette", self.character, "jnt_spine1" )
	if self.cl.baguetteActive then
		self.cl.baguetteEffect:start()
	end

	if not LogEntryManager.Cl_HasLog( LOGS.log_babywoc ) then
		self.cl.cryEffect = sm.effect.createEffect( "Babywoc - Cries", self.character )
		self.cl.cryEffect:start()
	end

	self.graphicsLoaded = true
end

function BabyWocCharacter.client_onGraphicsUnloaded( self )
	if self.cl.glowEffect then
		self.cl.glowEffect:destroy()
		self.cl.glowEffect = nil
	end
	if self.cl.glowstickEffect then
		self.cl.glowstickEffect:destroy()
		self.cl.glowstickEffect = nil
	end
	if self.cl.baguetteEffect then
		self.cl.baguetteEffect:destroy()
		self.cl.baguetteEffect = nil
	end
	if self.cl.cryEffect then
		self.cl.cryEffect:destroy()
		self.cl.cryEffect = nil
	end
	self.graphicsLoaded = false
end

function BabyWocCharacter.client_onUpdate( self, deltaTime )
	if not self.graphicsLoaded then
		return
	end

	if not LogEntryManager.Cl_HasLog( LOGS.log_babywoc ) then
		self.cl.animations.hang_loop.active = true
		self.cl.animations.hang_loop.weight = 1.0
	elseif self.cl.animations.hang_loop.active then
		self.cl.animations.hang_loop.active = false
		self.cl.animations.hang_loop.weight = 0.0
		self.cl.animations.hang_getup.active = true
		self.cl.animations.hang_getup.weight = 1.0
		self.cl.animations.hang_getup.time = 0
	end

	if self.cl.animations.hang_loop.active or self.cl.animations.hang_getup.active then
		self.character:setMovementWeights( 0, 0 )
	else
		self.character:setMovementWeights( 1, 1 )
	end

	-- Third person animations
	for name, animation in pairs(self.cl.animations) do
		if animation.info then
			animation.time = animation.time + deltaTime

			if animation.info.looping == true then
				if animation.time >= animation.info.duration then
					animation.time = animation.time - animation.info.duration
				end
			end
			if name == self.currentAnimation then
				animation.weight = math.min(animation.weight+(self.blendSpeed * deltaTime), 1.0)
				if animation.time >= animation.info.duration then
					self.currentAnimation = ""
				end
			elseif animation.active then
				animation.weight = math.min(animation.weight+(self.blendSpeed * deltaTime), 1.0)
				if animation.time >= animation.info.duration and not ( animation.info.looping or animation.looping ) then
					animation.active = false
				end
			else
				animation.weight = math.max(animation.weight-(self.blendSpeed * deltaTime ), 0.0)
			end

			self.character:updateAnimation( animation.info.name, animation.time, animation.weight )
		end
	end
end

function BabyWocCharacter.client_onClientDataUpdate( self, data, channel )
	self.cl.glowActive = data.glowstickState
	self.cl.baguetteActive = data.baguetteState

	if self.graphicsLoaded then
		if self.cl.baguetteActive and not self.cl.baguetteEffect:isPlaying() then
			self.cl.baguetteEffect:start()
		elseif not self.cl.baguetteActive and self.cl.baguetteEffect:isPlaying() then
			self.cl.baguetteEffect:stop()
			sm.effect.playEffect( "Babywoc - Unequip", self.character.worldPosition )
		end
		if self.cl.glowActive and not self.cl.glowEffect:isPlaying() then
			self.cl.glowEffect:start()
		elseif not self.cl.glowActive and self.cl.glowEffect:isPlaying() then
			self.cl.glowEffect:stop()
		end
		if self.cl.glowActive and not self.cl.glowstickEffect:isPlaying() then
			self.cl.glowstickEffect:start()
		elseif not self.cl.glowActive and self.cl.glowstickEffect:isPlaying() then
			self.cl.glowstickEffect:stop()
			sm.effect.playEffect( "Babywoc - Unequip", self.character.worldPosition )
		end
		self.character:setGlowMultiplier( self.cl.glowActive and 1 or 0 )
	end
end

function BabyWocCharacter.client_onEvent( self, event )
	self:cl_handleEvent( event )
end

function BabyWocCharacter.cl_handleEvent( self, event )
	if not self.graphicsLoaded then
		return
	end

	if event == "idlespecial01" then
		if self.cl.animations.idlespecial01 then
			self.currentAnimation = "idlespecial01"
			self.cl.animations.idlespecial01.time = 0
		end
	elseif event == "idlespecial02" then
		if self.cl.animations.idlespecial02 then
			self.currentAnimation = "idlespecial02"
			self.cl.animations.idlespecial02.time = 0
		end
	elseif event == "cow_eat_grass" then
		if self.cl.animations.cow_eat_grass then
			self.currentAnimation = "cow_eat_grass"
			self.cl.animations.cow_eat_grass.time = 0
		end
	elseif event == "moo" then
		if self.graphicsLoaded then
			sm.effect.playHostedEffect("Babywoc - Moo", self.character, "jnt_head" )
		end
	end
end