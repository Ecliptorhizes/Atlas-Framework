--[[
ResourceManager
A lightweight cleanup helper for Atlas framework modules.

This module tracks disposable resources such as RBXScriptConnections,
Instances, callbacks, and tasks. Add resources with `ResourceManager:Add`
and clean them all up safely with `ResourceManager:Destroy`.
]]

local ResourceManager = {}
ResourceManager.__index = ResourceManager

export type CleanupItem = RBXScriptConnection | Instance | thread | () -> () | { Destroy: () -> () } | { Disconnect: () -> () }

function ResourceManager.new()
    local self = setmetatable({}, ResourceManager)

    self._resources = {}
    self._destroyed = false

    return self
end

-- Adds a resource to the manager. Accepts instances, connections, threads,
-- callbacks, and tables that expose `Destroy` or `Disconnect` methods.
function ResourceManager:Add(resource: CleanupItem?)
    if resource == nil then
        return nil
    end

    assert(not self._destroyed, "ResourceManager has already been destroyed")
    table.insert(self._resources, resource)

    return resource
end

-- Destroys all tracked resources. Safe to call multiple times.
function ResourceManager:Destroy()
    if self._destroyed then
        return
    end

    self._destroyed = true

    for index = #self._resources, 1, -1 do
        local resource = self._resources[index]
        self._resources[index] = nil

        local resourceType = typeof(resource)
        if resourceType == "RBXScriptConnection" then
            resource:Disconnect()
        elseif resourceType == "Instance" then
            resource:Destroy()
        elseif resourceType == "thread" then
            task.cancel(resource)
        elseif resourceType == "function" then
            local success, err = pcall(resource)
            if not success then
                warn("ResourceManager callback error:", err)
            end
        elseif resourceType == "table" then
            if typeof(resource.Destroy) == "function" then
                resource:Destroy()
            elseif typeof(resource.Disconnect) == "function" then
                resource:Disconnect()
            end
        end
    end
end

return ResourceManager
