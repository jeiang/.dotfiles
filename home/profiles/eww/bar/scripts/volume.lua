#!/usr/bin/env nix-shell
--[[
#!nix-shell -i lua -p lua5_3_compat lua53Packages.dkjson pulseaudio
]]
local json = require("dkjson")

local function get_status(device)
    local cmd = io.popen("wpctl get-volume " .. device)
    if not cmd then return nil, nil end
    local output = cmd:read("*a")
    -- wpctl outputs in the format %.2f between 0 and 1 | boosted limit
    local _, _, volume = string.find(output, "Volume: (%d%.%d%d)")
    -- Convert to integer
    volume = math.floor(tonumber(volume) * 100)
    -- because the volume is fixed size, muted can be checked after this
    local muted = string.find(output, "[MUTED]", 12, true)
    local is_muted = not not muted     -- Coerce to bool
    return volume, is_muted
end

local function print_audio_state()
    local speaker_volume, speaker_muted = get_status("@DEFAULT_AUDIO_SINK@")
    local mic_volume, mic_muted = get_status("@DEFAULT_AUDIO_SOURCE@")

    local state = {
        mic_icon = nil,
        speaker_icon = nil,
        speaker = speaker_volume,
        mic = mic_volume
    }

    if speaker_muted then
        state.speaker_icon = "󰝟"
    elseif speaker_volume < 10 then
        state.speaker_icon = "󰕿"
    elseif speaker_volume < 60 then
        state.speaker_icon = "󰖀"
    else
        state.speaker_icon = "󰕾"
    end

    if mic_muted then
        state.mic_icon = ""
    else
        state.mic_icon = ""
    end

    print(json.encode(state))
end

-- Program Start
print_audio_state()
local notifier = io.popen("pactl subscribe", "r")
if not notifier then os.exit(false) end
local line = ""
while true do
    ::continue::
    line = notifier:read("*l")
    if not line then
        goto continue
    end
    if string.find(line, "change", 1, true) then
        print_audio_state()
    end
end
