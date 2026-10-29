-- Inert replacement for the vanilla block-container ("block stack") shape
-- 3d127db0-da28-4483-86fd-3eeed20fb85d.
--
-- The vanilla block stores items in an itemStack container, which is what
-- makes the "40 free component kits" blueprint work. This replacement has no
-- itemStack; if a blueprint still manages to attach a container, it is
-- emptied and removed during the first ticks after creation.

blockstack_dummy = class()

local ClearTicks = 40

function blockstack_dummy:server_onCreate()
	self.clearTicks = ClearTicks
end

function blockstack_dummy:server_onFixedUpdate()
	if self.clearTicks == nil then
		return
	end
	if self.clearTicks <= 0 then
		self.clearTicks = nil
		return
	end
	self.clearTicks = self.clearTicks - 1

	local interactable = self.interactable
	if interactable == nil then
		return
	end

	local container = interactable:getContainer( 0 )
	if container == nil then
		return
	end

	for slot = 0, container:getSize() - 1 do
		local item = container:getItem( slot )
		if item ~= nil and item.uuid ~= nil and item.quantity ~= nil and item.quantity > 0 then
			if sm.container.beginTransaction() then
				sm.container.spend( container, item.uuid, item.quantity, true )
				sm.container.endTransaction()
			end
		end
	end

	if container:isEmpty() then
		interactable:removeContainer( 0 )
	end
end
