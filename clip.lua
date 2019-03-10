-- Copyright (C) 2017  ParadoxSpiral
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with Parabot.  If not, see <http://www.gnu.org/licenses/>.


-- Encode a clip of the current file

local mp = require 'mp'
local options = require 'mp.options'

require 'os'

-- Options
local o = {
	-- Key bindings
	key_set_start_frame = "c",
	key_set_stop_frame = "C",
	key_start_lossless = "ctrl+C",
	key_start_encode = "ctrl+E",
	key_start_gif = "ctrl+G",

	-- Audio settings
	audio_codec = "libopus",
	audio_bitrate = "192k",

	-- Video settings (encode)
	video_codec = "libx265",
	video_crf = "25",
	video_pixel_format = "yuv420p10",
	video_width = "", -- source width if not specified
	video_height= "", -- source height if not specified
	video_upscale = false, -- upscale if video res is lower than desired res
	video_container = "mkv",

	-- Video settings (gif)
	gif_fps = "14",
	gif_scale = "480x270",
	gif_optimize = true,

	-- Misc settings
	encoding_preset = "medium", -- empty for no preset
	output_directory = "clip",
	clear_start_stop_on_encode = false,
	block_exit = true, -- stop mpv from quitting before the encode finished, if false…
		-- …mpv will quit but ffmpeg will be kept alive
}
options.read_options(o)

-- Global mutable variables
local start_frame = nil
local stop_frame = nil
local clip_type = 0 -- 0->lossless, 1->x265, 2->gif

function encode()
	if not start_frame then
		mp.osd_message("No start frame set!")
		return
	end
	if not stop_frame then
		mp.osd_message("No stop frame set!")
		return
	end
	if start_frame == stop_frame then
		mp.osd_message("Cannot create zero length clip!", 1.5)
	end

	local path = mp.get_property("path")
	local filename = mp.get_property("filename")
	local fileExt = filename:match("^.+%.(.+)$")

	local currentDir = string.sub(path, 1, string.len(path)-string.len(filename))

	local out = currentDir..o.output_directory.."/"..mp.get_property("media-title").."-clip-"..start_frame..
		"-"..stop_frame
	local width = mp.get_property("width")
	local height = mp.get_property("height")
	if o.video_width ~= "" and (o.video_width < width or o.video_upscale) then
		width = o.video_width
	end
	if o.video_height ~= "" and (o.video_height < height or o.video_upscale) then
		height = o.video_height
	end

	local saf = start_frame
	local sof = stop_frame
	if o.clear_start_stop_on_encode then
		start_frame = nil
		stop_fram = nil
	end

	local preset = ""
	if o.encoding_preset ~= "" then
		preset = "-preset "..o.encoding_preset
	end

	-- Check if ytdl is needed
	local input
	if not os.execute('ffprobe "'..path..'"') then
		input = '/usr/local/bin/youtube-dl "'..path..'" -o - | ffmpeg -ss '..saf..' -i -'
	else
		if clip_type == 2 then
			input = '/usr/local/bin/ffmpeg -ss '..saf..' -t '..sof-saf..' -i "'..path..'"'
		else
			input = '/usr/local/bin/ffmpeg -ss '..saf..' -i "'..path..'"'
		end
	end

	-- FIXME: Map metadata properly, like chapters or embedded fonts
	local command = input
	local precommand = input
	--local endcommand = "/usr/local/bin/imageoptim \""..out..".gif\""
	--local endcommand = "/usr/local/bin/imageoptim "..'"'..out..".gif"..'"'
	--local endcommand = "/usr/local/bin/imageoptim '"..currentDir..o.output_directory.."/*.gif'" -- all gif image
	--local endcommand = "/usr/local/bin/gifsicle -O2 -o "..'"'..out..'" "'..out..'"'

	if clip_type == 0 then
		command = command.." -t "..sof-saf.." -c:v copy -c:a copy"..' "'..out.."."..fileExt..'"'

	elseif clip_type == 1 then
		command = command.." -t "..sof-saf.." -c:a "..o.audio_codec.." -b:a "..o.audio_bitrate.." -c:v "..o.video_codec..
			" -pix_fmt "..o.video_pixel_format.." -crf "..o.video_crf.." -s "..width.."x"..
			height.." "..preset..' "'..out.."."..o.video_container..'"'

	elseif clip_type == 2 then
		local baseOpt = "fps="..o.gif_fps..",scale="..o.gif_scale
		precommand = command.." -vf \""..baseOpt..":flags=lanczos,palettegen\" -y /tmp/palette.png"
		command = command.." -i /tmp/palette.png -lavfi \""..baseOpt..":flags=lanczos [x]; [x][1:v] paletteuse\""..' "'..out..".gif"..'"'
		--os.execute("echo "..precommand.." | pbcopy")
		--os.execute("echo "..command.." | pbcopy")
		--os.execute("echo "..endcommand.." | pbcopy")
	end

	local time = os.time()

	startMsg = "Starting encode from "..saf.." to "..sof
	os.execute("osascript -e 'display notification \""..startMsg.."\" with title \"mpv\"'")
	mp.osd_message(startMsg, 3.5)

	if o.block_exit then
		--endMsg = "in $(expr \\( `date +%s` \\) - "..time..") seconds"
		if clip_type == 2 then
			os.execute(precommand)
			os.execute(command)
			--os.execute(endcommand)
			os.execute("osascript -e 'display notification \"End\" with title \"mpv\" sound name \"glass\"'")
		else
			os.execute(command.." && osascript -e 'display notification \"End\" with title \"mpv\" sound name \"glass\"'")
		end

		--os.execute(command)
		--mp.osd_message("Finished encode of "..out.." in "..os.time()-time.." seconds", 3.5)
		--endMsg = "Finished encode from "..saf.." to "..sof.." in "..os.time()-time.." seconds"
		--os.execute("osascript -e 'display notification \""..endMsg.."\" with title \"mpv\" sound name \"glass\"'")
		--mp.osd_message(endMsg, 3.5)
	else
		-- FIXME: Won't work on Windows, because of special snowflake pipe naming
		local ipc = mp.get_property("input-ipc-server")
		local del_tmp = ""
		if ipc == "" then
			ipc = os.tmpname()
			mp.set_property("input-ipc-server", ipc)
			del_tmp = " && lua -e 'os.remove(\""..ipc.."\")'"
		end
		os.execute(command..' && echo "{ \\"command\\": [\\"show-text\\", \\"Finished encode of \''
			..out..'\' in $(lua -e "print(os.time()-'..time..')") seconds\\", 3500] }" | socat - '
			..ipc..del_tmp.." &")
	end
end

-- Start frame key binding
mp.add_key_binding(o.key_set_start_frame, "clip-start",
	function()
		start_frame = mp.get_property("playback-time")
		if not start_frame then
			start_frame = 0
		end
		mp.osd_message("Clip start at "..start_frame.."s")
	end)
-- Stop frame key binding
mp.add_key_binding(o.key_set_stop_frame, "clip-end",
	function()
		stop_frame = mp.get_property("playback-time")
		if not stop_frame then
			mp.osd_message("playback-time is nil! (file not yet loaded?)")
		else
			mp.osd_message("Clip end at "..stop_frame.."s")
		end
	end)
-- Start encode key binding
mp.add_key_binding(o.key_start_lossless, "clip-lossless",
	function()
		clip_type = 0
		encode()
	end)

mp.add_key_binding(o.key_start_encode, "clip-encode",
	function()
		clip_type = 1
		encode()
	end)

mp.add_key_binding(o.key_start_gif, "clip-gif",
	function()
		clip_type = 2
		encode()
	end)

-- Reset start/stop frame when a new file is loaded
mp.register_event("start-file",
	function()
		start_frame = nil
		stop_frame = nil
	end)
