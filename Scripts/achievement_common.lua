
function RoadRageAchievementCheck (creation)
	local creationBody = nil

	if type(creation) == "Shape" then
		if sm.exists(creation) then
			creationBody = creation.body
		end
	elseif type(creation) == "Body" then
		if sm.exists(creation) then
			creationBody = creation
		end
	else
		return
	end
	if creationBody and sm.exists(creationBody) and creationBody:isDynamic() then
		local bodies = creationBody:getCreationBodies()
		if #bodies > 1 then
			local playerIds = {}
			for _, body in pairs(bodies) do
				for _, character in pairs(body:getAllSeatedCharacter()) do
					local player = character:getPlayer()
					if player then
						playerIds[#playerIds + 1] = player:getId()
					end
				end
			end
			if #playerIds > 0 then
				local roadRageAchievementUid = "19ab54db-aefb-4120-8395-15a498638324"
				sm.achievement.seti(roadRageAchievementUid, 1, playerIds)
			end
		end
	end
end


