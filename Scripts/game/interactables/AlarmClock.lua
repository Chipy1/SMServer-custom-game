-- AlarmClock.lua --
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

---@class AlarmClock : ShapeClass
---@field sv table
---@field cl table
AlarmClock = class( nil )
AlarmClock.connectionOutput = sm.interactable.connectionType.logic
AlarmClock.connectionInput = sm.interactable.connectionType.none
AlarmClock.maxChildCount = 255
AlarmClock.maxParentCount = 0
AlarmClock.colorNormal = sm.color.new( 0xee2a7bff )
AlarmClock.colorHighlight = sm.color.new( 0xee2a7bff )

-------- Server --------

function AlarmClock.server_onCreate( self )
	self.sv = {}
	self.sv.nextAlarmIndex = 1
	self.sv.isActive = false

	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = { alarmHours = 12, alarmMinutes = 0, alarmSoundIndex = 1 }
	end
	
	self.storage:save( self.sv.saved )
	self.network:setClientData( self.sv.saved )

	self.sv.alarmValuesDirty = false
	self.sv.lastMinute = 0
end

function AlarmClock.server_onFixedUpdate( self, dt )
	if self.sv.alarmValuesDirty then
		self.storage:save( self.sv.saved )
		self.sv.alarmValuesDirty = false
		self.network:setClientData( self.sv.saved )
	end

	-- Interactable active state is a one-frame pulse for controller/logic connections
	if self.interactable.active then
		self.interactable.active = false
	end

	local hour, minutes = GetTimeOfDayHoursMinutes()
	if self.sv.lastMinute ~= minutes and hour == self.sv.saved.alarmHours and minutes == self.sv.saved.alarmMinutes then
		self.interactable.active = true
		if self.sv.saved.alarmSoundIndex ~= 5 then
			self.network:sendToClients( "cl_n_startAlarm" )
		end
	end

	self.sv.lastMinute = minutes
end

function AlarmClock.sv_n_setAlarmTime( self, data )
	if data.position == 1 then
		if data.positive then
			if self.sv.saved.alarmHours + 10 >= 24 then
				if self.sv.saved.alarmHours >= 20  then
					self.sv.saved.alarmHours = self.sv.saved.alarmHours % 10
				else
					self.sv.saved.alarmHours = 23
				end
			else
				self.sv.saved.alarmHours = ( self.sv.saved.alarmHours + 10 ) % 24
			end
		else
			if self.sv.saved.alarmHours - 10 < 0 then
				self.sv.saved.alarmHours = math.min( 23, self.sv.saved.alarmHours + 20 )
			else
				self.sv.saved.alarmHours = ( self.sv.saved.alarmHours - 10 ) % 24
			end
		end

	elseif data.position == 2 then
		if data.positive then
			self.sv.saved.alarmHours = ( self.sv.saved.alarmHours + 1 ) % 24
		else
			self.sv.saved.alarmHours = ( self.sv.saved.alarmHours - 1 ) % 24
		end

	elseif data.position == 3 then
		if data.positive then
			self.sv.saved.alarmMinutes = ( self.sv.saved.alarmMinutes + 10 ) % 60
		else
			self.sv.saved.alarmMinutes = ( self.sv.saved.alarmMinutes - 10 ) % 60
		end

	elseif data.position == 4 then
		if data.positive then
			self.sv.saved.alarmMinutes = ( self.sv.saved.alarmMinutes + 1 ) % 60
		else
			self.sv.saved.alarmMinutes = ( self.sv.saved.alarmMinutes - 1 ) % 60
		end
	end

	self.sv.alarmValuesDirty = true
end

function AlarmClock.sv_n_setAlarmSound( self, soundIndex )
	self.sv.saved.alarmSoundIndex = soundIndex
	self.sv.alarmValuesDirty = true
end

--------- Client ---------

function AlarmClock.client_onCreate( self )
	self.cl = {}
	self.cl.textEffect = sm.effect.createEffect( "Alarmclock - Text", self.interactable )
	self.cl.textEffect:setRotation( sm.quat.new( 0, 0, 0.707, 0.707 ) )
	self.cl.textEffect:setOffsetPosition ( sm.vec3.new( -0.195, 0.075, 0.1176 ) )

	self.cl.textEffect:setScale( sm.vec3.new( 0.75,0.75, 0.75 ) )
	self.cl.textEffect:setParameter( "Color", sm.color.new( 0, 0.53, 0.9, 0.9 ) )
	self.cl.textEffect:setParameter( "ASG", sm.vec3.new( 0, 0, 0.9 ) )
	self.cl.time = 0
	self.cl.textEffect:start()

	self.cl.alarmEffect = sm.effect.createEffect( "Alarmclock - Alarm", self.interactable )
	self.cl.alarmPreviewEffect = sm.effect.createEffect( "Alarmclock - AlarmPreview", self.interactable )

	self.cl.alarmHours = 12
	self.cl.alarmMinutes = 0
	self.cl.alarmSoundIndex = 1
	self.cl.alarmEffect:setParameter( "alarm", self.cl.alarmSoundIndex )
end

function AlarmClock.client_onDestroy( self, dt )
	if self.cl.guiInterface and self.cl.guiInterface:isActive() then
		self:cl_onClose()
	end
	self.cl.textEffect:destroy()
	self.cl.alarmEffect:destroy()
	self.cl.alarmPreviewEffect:destroy()
end

function AlarmClock.client_onClientDataUpdate( self, data )

	self.cl.alarmHours = data.alarmHours
	self.cl.alarmMinutes = data.alarmMinutes

	self.cl.alarmSoundIndex = data.alarmSoundIndex
	self.cl.alarmEffect:setParameter( "alarm", self.cl.alarmSoundIndex )
	
	if self.cl.guiInterface then
		if self.cl.guiInterface:isActive() then
			self:cl_updateGui()
		end
	end

end

function AlarmClock.cl_updateGui( self )
	local hourDouble = math.floor( self.cl.alarmHours / 10 )
	local hourSingle = math.floor( self.cl.alarmHours % 10 )

	local minuteDouble = math.floor( self.cl.alarmMinutes / 10 )
	local minuteSingle = math.floor( self.cl.alarmMinutes % 10 )

	self.cl.guiInterface:setText( "HourDoubleText", tostring( hourDouble ) )
	self.cl.guiInterface:setText( "HourSingleText", tostring( hourSingle ) )

	self.cl.guiInterface:setText( "MinuteDoubleText", tostring( minuteDouble ) )
	self.cl.guiInterface:setText( "MinuteSingleText", tostring( minuteSingle ) )

	self.cl.guiInterface:setButtonState( "SoundButton1", false )
	self.cl.guiInterface:setButtonState( "SoundButton2", false )
	self.cl.guiInterface:setButtonState( "SoundButton3", false )
	self.cl.guiInterface:setButtonState( "SoundButton4", false )
	self.cl.guiInterface:setButtonState( "Mute", false )
	
	if self.cl.alarmSoundIndex then
		if self.cl.alarmSoundIndex == 5 then
			self.cl.guiInterface:setButtonState( "Mute", true )
		else
			self.cl.guiInterface:setButtonState( "SoundButton"..self.cl.alarmSoundIndex, true )
		end
	end
end

function AlarmClock.client_onInteract( self, character, state )

	if state == true then
		self.cl.guiInterface = sm.gui.createGuiFromLayout( "$GAME_DATA/Gui/Layouts/Interactable/Interactable_AlarmClock.layout", true )
		self.cl.guiInterface:setOnCloseCallback( "cl_onClose" )
		self.cl.guiInterface:open()

		self:cl_updateGui()

		self.cl.guiInterface:setButtonCallback( "HourButton1Pos", "cl_handleAlarmTimeEdit")
		self.cl.guiInterface:setButtonCallback( "HourButton1Sub", "cl_handleAlarmTimeEdit")
		self.cl.guiInterface:setButtonCallback( "HourButton2Pos", "cl_handleAlarmTimeEdit")
		self.cl.guiInterface:setButtonCallback( "HourButton2Sub", "cl_handleAlarmTimeEdit")

		self.cl.guiInterface:setButtonCallback( "MinuteButton1Pos", "cl_handleAlarmTimeEdit")
		self.cl.guiInterface:setButtonCallback( "MinuteButton1Sub", "cl_handleAlarmTimeEdit")
		self.cl.guiInterface:setButtonCallback( "MinuteButton2Pos", "cl_handleAlarmTimeEdit")
		self.cl.guiInterface:setButtonCallback( "MinuteButton2Sub", "cl_handleAlarmTimeEdit")

		self.cl.guiInterface:setButtonCallback( "SoundButton1", "cl_handleAlarmSoundChange" )
		self.cl.guiInterface:setButtonCallback( "SoundButton2", "cl_handleAlarmSoundChange" )
		self.cl.guiInterface:setButtonCallback( "SoundButton3", "cl_handleAlarmSoundChange" )
		self.cl.guiInterface:setButtonCallback( "SoundButton4", "cl_handleAlarmSoundChange" )
		self.cl.guiInterface:setButtonCallback( "Mute", "cl_handleAlarmSoundChange" )
	end
end

function AlarmClock.cl_handleAlarmTimeEdit( self, buttonName )
	local position = 1
	local increase = true

	if buttonName == "HourButton1Sub" then
		increase = false
	elseif buttonName == "HourButton2Pos" then
		position = 2
	elseif buttonName == "HourButton2Sub" then
		position = 2
		increase = false
	elseif buttonName == "MinuteButton1Pos" then
		position = 3
	elseif buttonName == "MinuteButton1Sub" then
		position = 3
		increase = false
	elseif buttonName == "MinuteButton2Pos" then
		position = 4
	elseif buttonName == "MinuteButton2Sub" then
		position = 4
		increase = false
	end
	self:cl_updateAlarmTime( position, increase )
end

function AlarmClock.cl_handleAlarmSoundChange( self, buttonName )
	local soundIndex = 1
	if buttonName == "SoundButton2" then
		soundIndex = 2
	elseif buttonName == "SoundButton3" then
		soundIndex = 3
	elseif buttonName == "SoundButton4" then
		soundIndex = 4
	elseif buttonName == "Mute" then
		soundIndex = 5
	end

	if soundIndex == 5 then
		self.cl.alarmEffect:stop()
		self.cl.alarmPreviewEffect:stop()
	else
		if soundIndex == self.cl.alarmSoundIndex and self.cl.alarmPreviewEffect:isPlaying() then
			self.cl.alarmPreviewEffect:stop()
		else
			self.cl.alarmEffect:stop()
			self.cl.alarmEffect:setParameter( "alarm", soundIndex )
			
			self.cl.alarmPreviewEffect:stop()
			self.cl.alarmPreviewEffect:setParameter( "alarm", soundIndex )
			self.cl.alarmPreviewEffect:start()
		end
	end

	self.cl.alarmSoundIndex = soundIndex

	if self.cl.guiInterface and sm.exists(self.cl.guiInterface) and self.cl.guiInterface:isActive() then
		self:cl_updateGui()
	end

	self.network:sendToServer( "sv_n_setAlarmSound", soundIndex )
end

function AlarmClock.cl_updateAlarmTime( self, position, positive )
	local data = { position = position, positive = positive}
	self.network:sendToServer( "sv_n_setAlarmTime", data )
end

function AlarmClock.cl_onClose( self )
	if self.cl.guiInterface and sm.exists( self.cl.guiInterface ) then
		self.cl.guiInterface:close()
		self.cl.guiInterface:destroy()
	end
	self.cl.guiInterface = nil
	if self.cl.alarmPreviewEffect:isPlaying() then
		self.cl.alarmPreviewEffect:stop()
	end
end

function AlarmClock.client_onUpdate( self, dt )
end

function AlarmClock.client_onFixedUpdate( self )
	self.cl.textEffect:setParameter( "TextContent", getTimeOfDayString() )
end

function AlarmClock.cl_n_startAlarm( self )
	if not self.cl.alarmEffect:isPlaying() then
		self.cl.alarmEffect:start()
	end
end
