#!/usr/bin/env nix-shell
--[[
#!nix-shell -i lua -p lua5_3_compat lua53Packages.luaposix
]]
-- Constants
BUF_SIZE = 2 ^ 13

HYPRCTL_GET_WORKSPACES =
"hyprctl workspaces | grep ID | sed 's/()/(1)/g' | sort | awk 'NR>1{print $1}' RS='(' FS=')' | sort -n"
HYPRCTL_GET_ACTIVE_WORKSPACES =
"hyprctl monitors | grep active | sed 's/()/(1)/g' | sort | awk 'NR>1{print $1}' RS='(' FS=')' | sort -n"

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


local function get_workspaces(active)
    local aw = nil
    if active then
        aw = io.popen(HYPRCTL_GET_ACTIVE_WORKSPACES, "r")
    else
        aw = io.popen(HYPRCTL_GET_WORKSPACES, "r")
    end
    if not aw then return nil end
    local workspaces = aw:read("*a")
    local ids = {}
    for str in string.gmatch(workspaces, "(%d+)") do
        local workspace_num = tonumber(str)
        if workspace_num then
            ids[workspace_num] = true
        end
    end
    aw:close()
    return ids
end

local function handle_workspace_change()
    local active_workspaces = get_workspaces(true)
    local all_workspaces = get_workspaces(false)
    if all_workspaces then
        local box = "(box :orientation \"v\" :spacing 1 :space-evenly \"true\" "

        for workspace in sortedPairs(all_workspaces) do
            if active_workspaces and active_workspaces[workspace] ~= nil then
                box = box .. "(button :class \"active\" :onclick \"hyprctl dispatch workspace " ..
                    workspace .. " \" \"\")"
            else
                box = box ..
                    "(button :class \"inactive\" :onclick \"hyprctl dispatch workspace " .. workspace .. " \" \"\")"
            end
        end
        box = box .. ")"
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
