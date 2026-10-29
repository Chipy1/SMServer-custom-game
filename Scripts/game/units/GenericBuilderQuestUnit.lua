dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"

GenericBuilderQuestUnit = class( nil )

local TargetPlayerDistance = 14 - 2
local UntargetPlayerDistance = 14 + 2


function GenericBuilderQuestUnit.server_onCreate( self )
    -- Idle
    self.idleState = self.unit:createState( "idle" )
    self.idleState.debugName = "idleState"

    self.currentState = self.idleState
    self.currentState:start()

    self.target = nil

    self.switchTargetCooldown = 0.0
    
    self.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.unit.character )
end

function GenericBuilderQuestUnit.server_onFixedUpdate( self, dt )
    if self.questName == nil then
		local value = TileStorageManager.Sv_GetValue( self.tileStorageKey, BUILDERGUIDE_PLATFORM_TABLE )
		if value and not IsEmptyTable( value ) then
			self.questName = value.questName
		end
	end

    self.switchTargetCooldown = self.switchTargetCooldown - 1
    self.switchTargetCooldown = math.max( self.switchTargetCooldown, 0 )

    if self.currentState then
        self.currentState:onFixedUpdate( dt )

        local followPlayer = true
        if self.unit.character:getCharacterType() == unit_builderguideFarmersleepy then
            followPlayer = not QuestManager.Sv_IsQuestComplete( self.questName ) -- stop follow when sleeping
        elseif self.unit.character:getCharacterType() == unit_builderguideFarmerko then
            local stage = QuestManager.Sv_GetQuestStage( self.questName )
            followPlayer = QuestManager.Sv_IsQuestComplete( self.questName ) or stage == GenericBuilderQuest.Stages.talk_to_person -- follow after revived
        end

        if not followPlayer then
            return
        end

        if self.currentState == self.idleState then
            local closestPlayer = GetClosestPlayer( self.unit.character.worldPosition, nil, self.unit.character:getWorld() )
			if closestPlayer and sm.exists( closestPlayer.character ) then
                local distance = sm.vec3.getDistance( closestPlayer.character.worldPosition, self.unit.character.worldPosition )
                if distance <= TargetPlayerDistance  then
                    if self.target ~= closestPlayer and self.switchTargetCooldown == 0 then
                        self.target = closestPlayer
                        self:sv_updateCharacterTarget()
                        self.switchTargetCooldown = 80
                    end
                elseif distance >= UntargetPlayerDistance  then
                    if self.target ~= nil then
                        self.target = nil
                        self:sv_updateCharacterTarget()
                    end
                end
			end
        end

        if self.unit.character:getCharacterType() == unit_builderguideWoc then
            return
        end

        if self.target and sm.exists( self.target ) then
            local facingDirection = ( self.target.character.worldPosition - self.unit.character.worldPosition ):safeNormalize( self.currentState:getFacingDirection() )
            self.unit:setFacingDirection( facingDirection )
        end
    end
end

function GenericBuilderQuestUnit.server_onUnitUpdate( self, dt )
    if not sm.exists( self.unit ) then
        return
    end
    if self.currentState then
        self.currentState:onUnitUpdate( dt )
    end
end

function GenericBuilderQuestUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_n_updateTarget", { target = self.target and self.target:getCharacter() or nil } )
	end
end