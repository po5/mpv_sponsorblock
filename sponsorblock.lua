-- sponsorblock.lua
--
-- This script skips sponsored segments of YouTube videos
-- using data from https://github.com/ajayyy/SponsorBlock

local options = {
    -- If true, sponsored segments will only be skipped once
    skip_once = true,

    -- Note that sponsored segments may ocasionally be inaccurate if this is turned off
    -- see https://ajay.app/blog.html#voting-and-pseudo-randomness-or-sponsorblock-or-youtube-sponsorship-segment-blocker
    local_database = true,

    -- Update database on first run, does nothing if local_database is false
    auto_update = true
}

mp.options = require "mp.options"
mp.options.read_options(options, "sponsorblock")

local utils = require "mp.utils"
local scripts_dir = mp.command_native({"expand-path", "~~home/scripts"})
local sponsorblock = utils.join_path(scripts_dir, "shared/sponsorblock.py")
local database_file = options.local_database and utils.join_path(scripts_dir, "shared/sponsorblock.db") or ""
local youtube_id = nil
local ranges = {}
local path = nil
local init = false

function file_exists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

function getranges(success, result, err)
    local sponsors = mp.command_native{name = "subprocess", capture_stdout = true, playback_only = false, args = {
        "python",
        sponsorblock,
        "ranges",
        database_file,
        youtube_id
    }}
    if not string.match(sponsors.stdout, "^%s*(.*%S)") then return end
    local current_path = mp.get_property("path")
    local current_ranges = {}
    if path == current_path then
        for _, t in ipairs(ranges) do
            current_ranges[tostring(t.start_time) .. "-" .. tostring(t.end_time)] = t.skipped
        end
    end
    path = current_path
    for t in string.gmatch(sponsors.stdout, "[^:]+") do
        start_time = tonumber(string.match(t, '[^,]+'))
        end_time = tonumber(string.match(t, '[^,]+$'))
        table.insert(ranges, {
            start_time = start_time,
            end_time = end_time,
            skipped = current_ranges[tostring(start_time) .. "-" .. tostring(end_time)]
        })
    end
end

function skip_ads(name, pos)
    if pos == nil then return end
    for _, t in ipairs(ranges) do
        if (not options.skip_once or not t.skipped) and t.start_time <= pos and t.end_time > pos then
            mp.set_property("time-pos", t.end_time)
            mp.osd_message("[sponsorblock] sponsor skipped")
            t.skipped = true
        end
    end
end

function file_loaded()
    local initialized = init
    ranges = {}
    local video_path = mp.get_property("path")
    local youtube_id1 = string.match(video_path, "https?://youtu%.be/([%a%d%-_]+).*")
    local youtube_id2 = string.match(video_path, "https?://w?w?w?%.?youtube%.com/v/([%a%d%-_]+).*")
    local youtube_id3 = string.match(video_path, "https?://w?w?w?%.?youtube%.com/watch%?v=([%a%d%-_]+).*")
    local youtube_id4 = string.match(video_path, "https?://w?w?w?%.?youtube%.com/embed/([%a%d%-_]+).*")
    youtube_id = youtube_id1 or youtube_id2 or youtube_id3 or youtube_id4
    if not youtube_id then return end
    init = true
    if not options.local_database or file_exists(database_file) then
        getranges()
    end
    if initialized then return end
    mp.observe_property("time-pos", "native", skip_ads)
    if not options.local_database or not options.auto_update then return end
    if options.auto_update then
        mp.command_native_async({name = "subprocess", playback_only = false, args = {
            "python",
            sponsorblock,
            "update",
            database_file
        }}, getranges)
    end
end

mp.register_event("file-loaded", file_loaded)
