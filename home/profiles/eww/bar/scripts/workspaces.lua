#!/usr/bin/env cached-nix-shell
--[[
#!nix-shell -i lua -p lua5_3_compat lua53Packages.luaposix lua53Packages.dkjson
]]
-- Constants
local json = require("dkjson")

-- Functions
local function sortedPairs(t, sort)
    local function collect_keys(t_inner, sort_inner)
        local _k = {}
        for k in pairs(t_inner) do
            _k[#_k + 1] = k
        end
        table.sort(_k, sort_inner)
        return _k
    end

    local keys = collect_keys(t, sort)
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end


local HYPRCTL_GET_WORKSPACES = "hyprctl workspaces -j"
local HYPRCTL_GET_ACTIVE_WORKSPACES = "hyprctl monitors -j"

local function get_workspaces(active)
    local aw = nil
    if active then
        aw = io.popen(HYPRCTL_GET_ACTIVE_WORKSPACES, "r")
    else
        aw = io.popen(HYPRCTL_GET_WORKSPACES, "r")
    end
    if not aw then return nil end
    local output = aw:read("*a")

    local workspaces, _, err = json.decode(output, 1, nil)
    if err then
        return nil
    else
        return workspaces
    end
end

local function handle_workspace_change()
    local monitors = get_workspaces(true)
    local active_workspaces = {}

    if monitors then
        for i = 1, #monitors do
            active_workspaces[monitors[i].activeWorkspace.id] = true
        end
    end

    local all_workspaces = get_workspaces(false)
    if all_workspaces then
        local box =
        '(eventbox :onscroll "echo {} | sed -e \\"s/up/-1/g\\" -e \\"s/down/+1/g\\" | xargs hyprctl dispatch workspace" (box :orientation \"v\" :spacing 1 :space-evenly \"true\" '

        local workspace_ids = {}

        for i = 1, #all_workspaces do
            workspace_ids[all_workspaces[i].id] = true
        end

        for workspace in sortedPairs(workspace_ids) do
            if active_workspaces and active_workspaces[workspace] ~= nil then
                box = box .. "(button :class \"active\" :onclick \"hyprctl dispatch workspace " ..
                    workspace .. " \" \"●\")"
            else
                box = box ..
                    "(button :class \"inactive\" :onclick \"hyprctl dispatch workspace " .. workspace .. " \" \"●\")"
            end
        end
        box = box .. "))"
        print(box)
    end
end


-- Program Start
local hyprland_signature = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")

if hyprland_signature == nil then
    return
end
SOCKET = "/tmp/hypr/" .. hyprland_signature .. "/.socket2.sock"

local socket = require("posix.sys.socket")
local fd = assert(socket.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0))
assert(socket.connect(fd, { family = socket.AF_UNIX, path = SOCKET }))

-- Initialize workspaces
handle_workspace_change()

local BUF_SIZE = 2 ^ 13

while true do
    -- Detect when hyprland says they did something
    local lines = socket.recv(fd, BUF_SIZE);
    if lines then
        -- If matched a workspace change, then handle it
        for _ in string.gmatch(lines, "workspace>>[^\n]+\n") do
            handle_workspace_change()
        end
    end
end
