dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"

QuestLootPhone = class( nil )

function QuestLootPhone.server_onCreate( self )
    self.sv = {}
    self.sv.done = false
end

function QuestLootPhone.server_onRemoved( self )
    self:sv_n_pickUpCall()
end

function QuestLootPhone.sv_n_pickUpCall( self )
    if not self.sv.done then
        self.sv.done = true
        DialogManager.Sv_PlayDialogBeat( "pick_up_phone_in_mechanic_station", nil )
        NotificationManager.Sv_LogUnlock( "phone" )
        local params = {
            questName = "quest_mystery_call",
            tickDelay = 20 * 40,
            prerequisiteQuest = "quest_mechanicstation",
            dialogUuid = dialog_phone_quest,
            dialogEntry = "FirstContact",
            dialogType = DialogType.Call,
            dialogSpeaker = DialogSpeakerName.Mysterious
        }





	    sm.scriptableObject.createScriptableObject( sm.uuid.new( "9dde94ad-6524-4e1d-9024-1210c0ab659d" ), params )
        self.harvestable:destroy()
    end
end

--Client

function QuestLootPhone.client_onCreate( self )
    self.cl = {}
    self.cl.rotation = math.random() * math.pi * 2
    self.cl.audioEffect = sm.effect.createEffect( "Quest - MechanicStationPhone", self.harvestable )
    self.cl.itemEffect = sm.effect.createEffect( "Questeffects - Quest_lootitem" )
    self.cl.itemEffect:setPosition( self.harvestable.worldPosition )
    local uid = sm.uuid.new( "e1828741-2653-4a9c-8850-3f5b7eee37a9" )
    self.cl.itemEffect:setParameter( "uuid", uid )
    self.cl.itemEffect:setParameter( "Color", sm.shape.getShapeTypeColor( uid ) )
    local bounds = sm.item.getShapeSize( uid )
    local scale = sm.construction.constants.subdivideRatio / ( ( bounds.x + bounds.y + bounds.z ) / 3.0 );
    self.cl.itemEffect:setScale( sm.vec3.new( scale, scale, scale ) )
    self.cl.audioEffect:start()
    self.cl.itemEffect:start()
end

function QuestLootPhone.client_onDestroy( self )
    if self.cl.audioEffect then
        self.cl.audioEffect:stop()
    end
    if self.cl.itemEffect then
        self.cl.itemEffect:stop()
    end
end

function QuestLootPhone.client_onUpdate( self, dt )
    local rotationSpeed = 0.1875 -- Revolutions per second
	self.cl.rotation = self.cl.rotation + math.pi * 2 * dt * rotationSpeed
	while self.cl.rotation > math.pi * 2 do
		self.cl.rotation = self.cl.rotation - math.pi * 2
	end
	self.cl.rotation = math.max( math.min( self.cl.rotation, math.pi * 2 ), 0 )
	local forward = sm.vec3.new( 0, 1, 0 )
	self.cl.itemEffect:setRotation( sm.vec3.getRotation( forward, forward:rotateZ( self.cl.rotation ) ) )
end

function QuestLootPhone.client_canInteract( self )
    local keyBindingText = GetInteractionKeybinding()
    sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PICK_UP}" )
    return true
end

function QuestLootPhone.client_onInteract( self, state )
    if state then
        self.network:sendToServer( "sv_n_pickUpCall" )
    end
end