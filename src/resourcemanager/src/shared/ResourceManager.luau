--[[
ResourceManager
A lightweight cleanup helper for Atlas framework modules.

This module tracks disposable resources such as RBXScriptConnections,
Instances, callbacks, and tasks. Add resources with 'ResourceManager:Add'
and clean them up safely with 'ResourceManager:Destroy'.
]]

local ResourceManager = {}
ResourceManager.__index = ResourceManager

export type CleanupItem = RBXScriptConnection | Instance | thread | (() -> ())


function ResourceManager.new()
    local self = setmetatable({}, ResourceManager)
    self._resources = {}
    self._destroyed = false
    return self
end

-- Adds a resource to the manager. Accepts instances, connections, threads,
-- callbacks, and tables that expose `Destroy` or `Disconnect` methods.

function ResourceManager:Add(resources: CleanupItem)
    if resources == nil then
        return nil
    end

    assert(not self._destroyed, "ResourceManager has already been destroyed.")
    table.insert(self._resources, resources)
    return resources
end

-- Destroys all tracked resources. Safe to call multiple times.
function ResourceManager:Destroy()
    if self._destroyed then
        return
    end

    self._destroyed = true

    for index = #self._resources, 1, -1 do
        local resources = self._resources[index]
        self._resources[index] = nil

        local resourceType = typeof(resources)
        if resourceType == "RBXScriptConnection" then
            resources:Disconnect()
        elseif resourceType == "Instance" then
            resources:Destroy()
        elseif resourceType == "thread" then
            task.cancel(resources)
            elseif resourceType == "function" then
                local success, err = pcall(resources)
                if not success then
                    warn("Error while executing cleanup function:", err)
                    end
                elseif resourceType == "table" then
                    if type(resources.Destroy) == "function" then
                        resources:Destroy()
                    elseif type(resources.Disconnect) == "function" then
                        resources:Disconnect()
                    end
                end
            end
        end
return ResourceManager

