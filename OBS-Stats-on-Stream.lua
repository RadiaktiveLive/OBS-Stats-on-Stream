obs = obslua
local ffi = require("ffi")

ffi.cdef[[

	struct video_output;
	typedef struct video_output video_t;

	uint32_t video_output_get_skipped_frames(const video_t *video);
	uint32_t video_output_get_total_frames(const video_t *video);
	double video_output_get_frame_rate(const video_t *video);

	video_t *obs_get_video(void);
]]

local output_mode = "simple_stream";
local callback_delay = 1000;
local text_source = "";

local text_formatting = "";

local default_text_formatting = [[Missed frames: $missed_frames/$missed_total_frames ($missed_percents%)
Skipped frames: $skipped_frames/$skipped_total_frames ($skipped_percents%)
Dropped frames: $dropped_frames/$dropped_total_frames ($dropped_percents%)
Congestion: $congestion% (avg. $average_congestion%)
Average frame time: $average_frame_time ms
Memory Usage: $memory_usage MB
Bitrate: $bitrate kb/s
FPS: $fps]];


local lagged_frames_string = "";
local lagged_total_frames_string = "";
local lagged_percents_string = "";

local skipped_frames_string = "";
local skipped_total_frames_string = "";
local skipped_percents_string = "";

local dropped_frames_string = "";
local dropped_total_frames_string = "";
local dropped_percents_string = "";

local congestion_string = "";
local average_congestion_string = "";
local bitrate_string = "";

local memory_usage_string = "";
local fps_string = "";
local average_frame_time_string = "";

local last_bitrate = 0;
local last_bytes_sent = 0;
local last_bytes_sent_time = 0;

local is_script_enabled = true;
local is_timer_on = false;

local total_ticks = 0;
local congestion_cumulative = 0;
local bitrate_cumulative = 0;

local obsffi;
if ffi.os == "OSX" then
	obsffi = ffi.load("obs.0.dylib"); -- OS X
else
	obsffi = ffi.load("obs"); -- Windows
	-- Linux?
end

local my_settings = nil;

function timer_tick()
	total_ticks = total_ticks + 1;
	
	local source = obs.obs_get_source_by_name(text_source);
	
	-- Not working for some reason?
	-- I want to detect output mode automatically.
	--[[
	local dst = ""
	obs.os_get_config_path(dst, #dst, "obs-studio")
	print("path: " .. dst)
	--]]
	
	--local profile = obs.obs_frontend_get_current_profile()
	--print("profile: " .. profile)
	
	--local profile_path = "                                                                                                                                                                                                                                                               "
	--obs.os_get_config_path(profile_path, #profile_path, "obs-studio\\basic\\profiles\\" ..profile .. "\\basic.ini")
	--print("path: " .. profile_path)
	
	--local config = nil
	--local config_open_success = obs.config_open(config, profile_path, 0)
	--print("success: " .. tostring(config_open_success))
	
	--obs.config_close(config)
	
	--Not working for some reason?
	--local cpu_info = obs.os_cpu_usage_info_start();
	--local usage = obs.os_cpu_usage_info_query(cpu_info);
	--print(tostring(usage));
	--obs.os_cpu_usage_info_destroy(cpu_info);
	
	
	-- Get memory usage
	local memory_usage = obs.os_get_proc_resident_size() / (1024.0 * 1024.0);
	
	-- Get FPS/framerate
	local fps = obs.obs_get_active_fps();
	
	-- Get average time to render frame
	local average_frame_time = obs.obs_get_average_frame_time_ns() / 1000000.0;
	
	-- Get lagged/missed frames
	local rendered_frames = obs.obs_get_total_frames();
	local lagged_frames = obs.obs_get_lagged_frames();
	
	-- Get skipped frames
	local encoded_frames = 0;
	local skipped_frames = 0;
	
	if obsffi ~= nil then
		local video = obsffi.obs_get_video();
		if video ~= nil then
			encoded_frames = obsffi.video_output_get_total_frames(video);
			skipped_frames = obsffi.video_output_get_skipped_frames(video);
		end
	end
	
	-- Get dropped frames, congestion and total bytes
	local total_frames = 0;
	local dropped_frames = 0;
	local congestion = 0.0;
	local total_bytes = 0;

	local output = obs.obs_get_output_by_name(output_mode);
	-- output will be nil when not actually streaming
	if output ~= nil then
		total_frames = obs.obs_output_get_total_frames(output);
		dropped_frames = obs.obs_output_get_frames_dropped(output);
		congestion = obs.obs_output_get_congestion(output);
		total_bytes = obs.obs_output_get_total_bytes(output);
		--local connect_time = obs.obs_output_get_connect_time_ms(output)
		obs.obs_output_release(output);
	end
	
	congestion_cumulative = congestion_cumulative + congestion

	-- Get bitrate
	local bytes_sent = total_bytes;
	local current_time = obs.os_gettime_ns();

	if bytes_sent < last_bytes_sent then
		bytes_sent = 0;
	end
	if bytes_sent == 0 then
		last_bytes_sent = 0;
	end
		
	local time_passed = (current_time - last_bytes_sent_time) / 1000000000.0;
	local bits_between = (bytes_sent - last_bytes_sent) * 8;
	bitrate = bits_between / time_passed / 1000.0;


	local bitrate = last_bitrate;
	if time_passed > 2.0 then
		local bits_between = (bytes_sent - last_bytes_sent) * 8;
		bitrate = bits_between / time_passed / 1000.0;

		last_bytes_sent = bytes_sent;
		last_bytes_sent_time = current_time;
		last_bitrate = bitrate;
	end

	-- Update strings with new values
	lagged_frames_string = tostring(lagged_frames);
	lagged_total_frames_string = tostring(rendered_frames);
	lagged_percents_string = string.format("%.1f", 100.0 * lagged_frames / rendered_frames);

	skipped_frames_string = tostring(skipped_frames);
	skipped_total_frames_string = tostring(encoded_frames);
	skipped_percents_string = string.format("%.1f", 100.0 * skipped_frames / encoded_frames);

	dropped_frames_string = tostring(dropped_frames);
	dropped_total_frames_string = tostring(total_frames);
	dropped_percents_string = string.format("%.1f", 100.0 * dropped_frames / total_frames);

	congestion_string = string.format("%.2g", 100 * congestion);
	average_congestion_string = string.format("%.g", 100 * congestion_cumulative / total_ticks);
	
	average_frame_time_string = string.format("%.1f", average_frame_time);
	memory_usage_string = string.format("%.1f", memory_usage);
	bitrate_string = string.format("%.0f", bitrate);
	fps_string = string.format("%.2g", fps);
	
	
	-- Make a string for display in a text source
	local formatted_text = text_formatting;

	formatted_text = formatted_text:gsub("$missed_frames", lagged_frames_string);
	formatted_text = formatted_text:gsub("$missed_total_frames", lagged_total_frames_string);
	formatted_text = formatted_text:gsub("$missed_percents", lagged_percents_string);

	formatted_text = formatted_text:gsub("$skipped_frames", skipped_frames_string);
	formatted_text = formatted_text:gsub("$skipped_total_frames", skipped_total_frames_string);
	formatted_text = formatted_text:gsub("$skipped_percents", skipped_percents_string);

	formatted_text = formatted_text:gsub("$dropped_frames", dropped_frames_string);
	formatted_text = formatted_text:gsub("$dropped_total_frames", dropped_total_frames_string);
	formatted_text = formatted_text:gsub("$dropped_percents", dropped_percents_string);

	formatted_text = formatted_text:gsub("$congestion", congestion_string);
	formatted_text = formatted_text:gsub("$average_congestion",average_congestion_string);

	formatted_text = formatted_text:gsub("$average_frame_time", average_frame_time_string);
	formatted_text = formatted_text:gsub("$memory_usage", memory_usage_string);
	formatted_text = formatted_text:gsub("$bitrate", bitrate_string);
	formatted_text = formatted_text:gsub("$fps", fps_string);

	-- Update text source
	if source ~= nil then
		local settings = obs.obs_data_create();
		obs.obs_data_set_string(settings, "text", formatted_text);
		obs.obs_source_update(source, settings);
		obs.obs_source_release(source);
		obs.obs_data_release(settings);
	end
end

function reset_formatting(properties, property)
	text_formatting = default_text_formatting;

	obs.obs_data_set_string(my_settings, "text_formatting", default_text_formatting);
	obs.obs_properties_apply_settings(properties, my_settings);

	return true;
end

function on_event(event)
	if event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
		print("scene loaded");
		
		if is_script_enabled then
			print("script is enabled");
			is_timer_on = true;
			obs.timer_add(timer_tick, callback_delay);
		end
	end
end
		
function script_properties()
	local properties = obs.obs_properties_create();

	local enable_script_property = obs.obs_properties_add_bool(properties, "is_script_enabled", "Enable Script");

	local output_mode_property = obs.obs_properties_add_list(properties, "output_mode", "Output Mode", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING);
	obs.obs_property_list_add_string(output_mode_property, "Simple", "simple_stream");
	obs.obs_property_list_add_string(output_mode_property, "Advanced", "adv_stream");
	obs.obs_property_set_long_description(output_mode_property, "Must match the output mode you are using in OBS -> Settings -> Output -> Output mode.");
	
	local callback_delay_property = obs.obs_properties_add_int(properties, "callback_delay", "Update Delay (ms)", 100, 2000, 100);
	obs.obs_property_set_long_description(callback_delay_property, "Determines how often the data will update.");
	
	local text_source_property = obs.obs_properties_add_list(properties,
		"text_source", "Text Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING);
	local sources = obs.obs_enum_sources();
	if sources ~= nil then
		for _, source in ipairs(sources) do
			local source_id = obs.obs_source_get_id(source);
			if source_id == "text_gdiplus_v2" or source_id == "text_ft2_source_v2" then
				local name = obs.obs_source_get_name(source);
				obs.obs_property_list_add_string(text_source_property, name, name);
			end
		end
	end
	obs.source_list_release(sources);
	obs.obs_property_set_long_description(text_source_property, "Text source that will be used to display the data.");

	obs.obs_properties_add_text(properties, "text_formatting", "Text Formatting", obs.OBS_TEXT_MULTILINE);
	obs.obs_properties_add_button(properties, "reset_formatting_button", "Reset Formatting", reset_formatting);

	obs.obs_properties_apply_settings(properties, my_settings);

	return properties;
end

function script_defaults(settings)
	obs.obs_data_set_default_bool(settings, "is_script_enabled", true);
	obs.obs_data_set_default_string(settings, "output_mode", "simple_stream");
	obs.obs_data_set_default_int(settings, "callback_delay", 1000);
	obs.obs_data_set_default_string(settings, "text_source", "");
	obs.obs_data_set_default_string(settings, "text_formatting", default_text_formatting);
end

function script_update(settings)
	my_settings = settings;

	is_script_enabled = obs.obs_data_get_bool(settings, "is_script_enabled");
	output_mode = obs.obs_data_get_string(settings, "output_mode");
	callback_delay = obs.obs_data_get_int(settings, "callback_delay");
	text_source = obs.obs_data_get_string(settings, "text_source");

	text_formatting = obs.obs_data_get_string(settings, "text_formatting");

	if is_timer_on then
		obs.timer_remove(timer_tick);
		is_timer_on = false;
	end

	local source = obs.obs_get_source_by_name(text_source)

	if source == nil then
		print("No source found");
		is_timer_on = false;
		return;
	end
	
	obs.obs_source_release(source);
	
	if not is_script_enabled then
		print("Script is disabled");
		is_timer_on = false;
		return;
	end
	
	print("Script is reloaded");
	is_timer_on = true;
	obs.timer_add(timer_tick, callback_delay);
end

function script_description()
	return [[
<center><h2>OBS Stats on Stream v0.5</h2></center>
<center><a href="https://twitch.tv/GreenComfyTea">twitch.tv/GreenComfyTea</a> - 2021</center>
<center><p>Shows missed frames, skipped frames, dropped frames, congestion, bitrate, fps, memory usage and average frame time on stream as text source.</p></center>
<center><a href="https://github.com/GreenComfyTea/OBS-Stats-on-Stream/blob/main/Text-Formatting-Variables.md">Text Formatting Variables</a></center>
<hr/>
]];
end

function script_load(settings)
	print("script loaded");
	obs.obs_frontend_add_event_callback(on_event);
end