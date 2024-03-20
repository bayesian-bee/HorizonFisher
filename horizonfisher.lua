--[[
Copyright 2019-2020 Seth VanHeulen

This file is a fork of fisher, modified by Bee.

fisher is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

fisher is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with fisher.  If not, see <https://www.gnu.org/licenses/>.
--]]

-- luacheck: std lua51, globals _addon windower

_addon.name = 'HorizonFisher'
_addon.author = 'Bee (original addon written by Seth VanHeulen)'
_addon.description = 'HorizonXI fishing bot.'
_addon.version = '0.8.3'
_addon.commands = {'horizonfisher', 'hf'}

-- built-in libraries
local coroutine = require('coroutine')
local math = require('math')
local os = require('os')
local string = require('string')
local table = require('table')
local texts = require('texts')
-- extra libraries
local bit = require('bit')
local config = require('config')
require('pack')
-- local libraries
local data = require('data')
res = require 'resources'

local session
local settings
do
    local function initialize_session()
        session = {
            running=false, coroutine_key=math.random(),
            item_by_id={}, bait_by_id={},
            catch_limit=0,
        }
    end

    local settings_cache = {}

    local defaults = {
        equip_delay=2, move_delay=0, cast_attempt_delay=4, cast_attempt_max=10,
        release_delay=3, catch_delay_min=3, catch_delay_tweak=15, catch_delay_max=30, recast_delay=3,
        debug_messages=false, alert_command='',
		anti_gm = {
			alert_box = {
				pos={x=100,y=200}, 
				bg={alpha=255,red=180,green=0,blue=0},
				text={size=72,alpha=255,red=255,green=255,blue=255},
			},
			geofence = {
				enabled = false,
				heading_tolerance = 0.25,
				radius = 3,
			},
			dry_detection = {
				enabled = false,
				no_catch_limit=6,
			},
		}
    }

    local function load_settings(character)
        character = character or windower.ffxi.get_player().name
        if not settings_cache[character] then
            local path = string.format('data/%s.xml', character)
            settings_cache[character] = config.load(path, defaults)
        end
        return settings_cache[character]
    end

    local function initialize(character)
        initialize_session()
        settings = load_settings(character)
    end

    windower.register_event('login', initialize)

    if windower.ffxi.get_info().logged_in then initialize() end
end

local MESSAGE_INFO = 211 --Unity
local MESSAGE_WARN = 220 --Assist J
local MESSAGE_ERROR = 221 --Assist E
local MESSAGE_DEBUG = 222 --Assist E

local function message(text, level)
    local mode = level or MESSAGE_INFO
    if settings.debug_messages or mode ~= MESSAGE_DEBUG then
        windower.add_to_chat(mode, string.format('[%s] %s', 'HF', text))
    end
end

local function stop_fishing(reason)
    if session.running then
        session.running = false
        session.coroutine_key = math.random()
		if(settings.anti_gm.geofence.enabled) then
			session.geofence = nil
		end
		if(settings.anti_gm.dry_detection.enabled) then
			session.dry_detection = nil
		end
        if reason then
            message(string.format('stopped automated fishing (%s)', reason), MESSAGE_ERROR)
            if #settings.alert_command > 0 then
                windower.send_command(settings.alert_command)
            end
        else
            message('stopped automated fishing', MESSAGE_WARN)
        end
    end
end

local navigation
do
	require('vectors')

	local function get_my_position_and_speed()
		local my_mob_data = windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id)
		return {x=my_mob_data['x'], y=my_mob_data['y'], z=my_mob_data['z'], heading=my_mob_data['facing'], speed=my_mob_data['movement_speed']}
	end
	
	local function quadrant_correction(v)
		if(v[1] >= 0 and v[2] >= 0) then
			return 0
		elseif(v[1] < 0 and v[2] >= 0) then
			return math.pi
		elseif(v[1] < 0 and v[2] < 0) then
			return math.pi
		else
			return math.pi*2
		end
	end

	local function get_2d_vector_angle(v)
		return quadrant_correction(v) + math.atan(v[2] / v[1])
	end

	local function angle_of_vector_between_two_points(point1, point2)
		return get_2d_vector_angle(vector.subtract(point2, point1))
	end

	--navigate directly to target point.
	function snap_to_point(target_xpos, target_ypos, tolerance)

		local my_mob_data = get_my_position_and_speed()	

		local position_tolerance = tolerance --tolerance between current and target position
		local angle_tolerance = 0.05*math.pi --radians. tolerated distance between heading and target direction to choose new direction
		local two_radians = 2*math.pi
		--amount of time to walk. 
		--Coefficient < 1 guarantees convergence to target
		local step_time = 0.95*position_tolerance/my_mob_data['speed'] 
		local running = false
		local delta = math.sqrt(math.pow(my_mob_data['x'] - target_xpos, 2) + math.pow(my_mob_data['y'] - target_ypos, 2))
		while(delta > position_tolerance) do
			if(delta < 1) then
				windower.ffxi.toggle_walk(true)
			end
			my_mob_data = get_my_position_and_speed()
			delta = math.sqrt(math.pow(my_mob_data['x'] - target_xpos, 2) + math.pow(my_mob_data['y'] - target_ypos, 2))
			local direction = angle_of_vector_between_two_points(V({my_mob_data['x'], my_mob_data['y']}), V({target_xpos, target_ypos}))
			if((not running) or (math.abs(((-my_mob_data.heading) % two_radians) - (direction % two_radians)) > angle_tolerance)) then
				windower.ffxi.run(target_xpos - my_mob_data['x'], target_ypos - my_mob_data['y'])
				--windower.ffxi.run(direction)
				running = true
			end
			coroutine.sleep(step_time)
		end
		running = false
		windower.ffxi.toggle_walk(false)
		windower.ffxi.run(false)
	end
end

local geofence
do
	local alert_box = texts.new(settings.anti_gm.alert_box)
	
	local function press_key(key, duration)
		windower.send_command('setkey '..key..' down')
		if(not duration) then duration = 0.1 end
		coroutine.sleep(.1)
		windower.send_command('setkey '..key..' up')
	end
	
	function set_geofence()
		local player_data = windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id)
		session.geofence = {}
		session.geofence.zone = windower.ffxi.get_info().zone
		session.geofence.center = {x=player_data.x, y=player_data.y, z=player_data.z}
		session.geofence.radius = settings.anti_gm.geofence.radius
		session.geofence.initial_heading = player_data.heading
		session.geofence.heading_tolerance = settings.anti_gm.geofence.heading_tolerance --radian equivalent of 15 degrees
	end
	
	--returns character to its initial position upon starting to fish
	local function no_hoe_check()
		local initial_position = session.geofence.center
		local initial_heading = session.geofence.initial_heading
		stop_fishing('Geofence broken')
		message('Returning to fishing spot in 5...')
		coroutine.sleep(5)
		snap_to_point(initial_position.x, initial_position.y, 0.1)
		message('Resuming fishing in 3...')
		coroutine.sleep(1)
		windower.ffxi.turn(initial_heading)
		coroutine.sleep(1)
		windower.send_command('hf start')
	end
	
	local function anti_gm_alert_on_screen(alert_text)
		alert_box:text(alert_text)
		alert_box:visible(true)
	end
	
	function clear_alert()
		alert_box:text('')
		alert_box:visible(false)
	end
	
	function on_geofence_break()
		message('[Anti-GM] YOU HAVE MOVED!', MESSAGE_ERROR)
		anti_gm_alert_on_screen('YOU HAVE MOVED!')
		press_key('escape') --TODO: end ongoing fishing with packet injection.
		--act_natural()
		no_hoe_check()
	end
	
	--assumes radians
	local function angular_difference(angle1, angle2)
		local difference = (angle1 - angle2 + math.pi) % (2*math.pi) - math.pi
		if(difference < -math.pi) then difference = difference + 2*math.pi end
		return difference
	end
	
	function check_geofence()
		if(session.geofence) then
			local pd = windower.ffxi.get_mob_by_id(windower.ffxi.get_player().id)
			local gf = session.geofence.center
			local distance_from_geofence_center = math.sqrt((pd.x - gf.x)^2 + (pd.y - gf.y)^2 + (pd.z - gf.z)^2)
			local angular_distance_from_initial_heading = math.abs(angular_difference(pd.heading, session.geofence.initial_heading))
			
			if(distance_from_geofence_center >= session.geofence.radius) then
				message('Geofence distance break (distance=' .. tostring(distance_from_geofence_center) .. ')', MESSAGE_DEBUG)
				on_geofence_break()
			elseif(angular_distance_from_initial_heading >= math.abs(session.geofence.heading_tolerance)) then
				message('Geofence heading break (delta heading=' .. tostring(angular_distance_from_initial_heading) .. ')', MESSAGE_DEBUG)
				on_geofence_break()
			end			
		end
	end
	
end

local dry_detection
do
	
	local function vanadiel_minutes_to_real_seconds(vanadiel_minutes)
		return vanadiel_minutes*((57*60+36)/(60*24)) --seconds in a vana day / min in a real day
	end
	--This is when ASB restocks: 0,4,6,7,17,18,20
	function get_next_restock_vanadiel_time(current_time)
		if (current_time > (0*60)) and (current_time <= (4*60)) then
			return 4*60
		elseif (current_time > (4*60)) and (current_time <= (6*60)) then
			return 6*60
		elseif (current_time > (6*60)) and (current_time <= (7*60)) then
			return 7*60
		elseif (current_time > (7*60)) and (current_time <= (17*60)) then
			return 17*60
		elseif (current_time > (18*60)) and (current_time <= (20*60)) then
			return 20*60
		else
			return 24*60
		end
	end
	
	function initialize_dry_detection()
		session.dry_detection = {}
		session.dry_detection.no_catch_count = 0
		session.dry_detection.last_cast_time = nil
	end
	
	function is_dry()
		return session.dry_detection.no_catch_count >= settings.anti_gm.dry_detection.no_catch_limit
	end
	
	function should_reset_no_catch_count()
		local ingame_time = windower.ffxi.get_info().time
		if(session.dry_detection.last_cast_time) then
			local restock_after_cast = get_next_restock_vanadiel_time(session.dry_detection.last_cast_time)
			message(
				string.format('Current ingame time: %s, next restock time: %s', ingame_time, restock_after_cast),
				MESSAGE_DEBUG
			)
		end
		if session.dry_detection.last_cast_time 
			and (ingame_time >= get_next_restock_vanadiel_time(session.dry_detection.last_cast_time) 
				or (ingame_time < 60 and get_next_restock_vanadiel_time(session.dry_detection.last_cast_time)==(24*60))) then
			return true
		else
			return false
		end
	end
	
	function reset_no_catch_count()
		session.dry_detection.no_catch_count = 0
	end
	
	function increment_no_catch_count()
		session.dry_detection.no_catch_count = session.dry_detection.no_catch_count + 1
	end
	
	function get_delay_until_restock()
		local ingame_time = windower.ffxi.get_info().time
		local ingame_hour = math.floor(ingame_time/60)
		local next_restock_time = get_next_restock_vanadiel_time(ingame_time)
		return vanadiel_minutes_to_real_seconds(next_restock_time - ingame_time)
	end
	
	function schedule_delay_notifications(delay, restock_time)
		-- i cannot defeat lazy eval
		-- TODO(Bee): learn to code
		--
		-- local remaining_delay = math.floor(delay)
		-- local message_delay = 0
		-- local message_string = ''
		-- while(remaining_delay > 0) do
			-- message_string = 'Casting in ' .. tostring(remaining_delay) .. ' sec...'
			-- coroutine.schedule(
				-- function () a = (session.running and message(message_string, MESSAGE_INFO) or nil) end,
				-- message_delay
			-- )
			-- remaining_delay = remaining_delay - 30
			-- message_delay = message_delay + 30
		-- end
		local vana_hours = restock_time/60
		message(string.format('Awaiting restock @ %d:00...', vana_hours), MESSAGE_INFO)
	end
end

local get_equipped_item_id
do
    local bag_by_id = {
        [0]='inventory',
        [8]='wardrobe',
        [10]='wardrobe2',
        [11]='wardrobe3',
        [12]='wardrobe4',
    }

    function get_equipped_item_id(slot_name, items)
        items = items or windower.ffxi.get_items()
        local bag = items.equipment[slot_name .. '_bag']
        local bag_name = bag_by_id[bag]
        local slot = items.equipment[slot_name]
        local item = items[bag_name][slot]
        if item then return item.id end
    end
end

local function check_equipment()
    local items = windower.ffxi.get_items()
    local left_ring_id = get_equipped_item_id('left_ring', items)
    local right_ring_id = get_equipped_item_id('right_ring', items)
    if left_ring_id == 15556 or right_ring_id == 15556 then return false end
    local range_id = get_equipped_item_id('range', items)
    if range_id == 19319 then
        return windower.ffxi.get_info().zone == 86
    end
    return data.rod_modifiers_by_id[range_id] ~= nil
end

local input_fish_command
do
    local function equip_bait(item, bag)
        if item.status == 0 and session.bait_by_id[item.id] then
            message(string.format('equipping item: %d, %d, %d', item.slot, 3, bag), MESSAGE_DEBUG)
            windower.ffxi.set_equip(item.slot, 3, bag)
            coroutine.sleep(settings.equip_delay)
            return true
        end
    end

    local function check_bait()
        local items = windower.ffxi.get_items()
        local ammo_id = get_equipped_item_id('ammo', items)
        if session.bait_by_id[ammo_id] then return true end
        for slot = 1, items.max_inventory do
            if equip_bait(items.inventory[slot], 0) then return true end
        end
        for slot = 1, items.max_wardrobe do
            if equip_bait(items.wardrobe[slot], 8) then return true end
        end
        for slot = 1, items.max_wardrobe2 do
            if equip_bait(items.wardrobe2[slot], 10) then return true end
        end
        if items.enabled_wardrobe3 then
            for slot = 1, items.max_wardrobe3 do
                if equip_bait(items.wardrobe3[slot], 11) then return true end
            end
        end
        if items.enabled_wardrobe4 then
            for slot = 1, items.max_wardrobe4 do
                if equip_bait(items.wardrobe4[slot], 12) then return true end
            end
        end
        return false
    end

    local function store_item(target_bag, source_item)
        message(string.format('moving item: %d, %d, %d', target_bag, source_item.slot, source_item.count), MESSAGE_DEBUG)
        windower.ffxi.put_item(target_bag, source_item.slot, source_item.count)
        coroutine.sleep(settings.move_delay)
        return true
    end

    local function check_inventory()
        local items = windower.ffxi.get_items()
        if items.count_inventory < items.max_inventory then return true end
        local moved = false
        for slot = 1, items.max_inventory do
            local source_item = items.inventory[slot]
            if source_item.status == 0 and session.item_by_id[source_item.id] then
                if items.enabled_satchel and items.count_satchel < items.max_satchel then
                    moved = store_item(5, source_item)
                elseif items.enabled_sack and items.count_sack < items.max_sack then
                    moved = store_item(6, source_item)
                elseif items.enabled_case and items.count_case < items.max_case then
                    moved = store_item(7, source_item)
                else
                    return moved
                end
            end
        end
        return moved
    end

    function input_fish_command(coroutine_key)
        local cast_attempt = 0
        while session.running and coroutine_key == session.coroutine_key and cast_attempt < settings.cast_attempt_max do
            if not next(session.item_by_id) then
                stop_fishing('nothing set to catch')
            elseif not next(session.bait_by_id) then
                stop_fishing('no bait set to use')
            elseif not check_equipment() then
                stop_fishing('invalid equipment')
            elseif not check_bait() then
                stop_fishing('out of bait')
            elseif not check_inventory() then
                stop_fishing('out of inventory space')
            else
                cast_attempt = cast_attempt + 1
                message(string.format('inputting fish command: %d, %d', cast_attempt, settings.cast_attempt_max), MESSAGE_DEBUG)
                windower.send_command('input /fish')
                coroutine.sleep(settings.cast_attempt_delay)
            end
        end
        if coroutine_key == session.coroutine_key and cast_attempt >= settings.cast_attempt_max then
            stop_fishing('unable to cast')
        end
    end
end

local function schedule_cast(cast_delay)
    message(string.format('casting in %d seconds', cast_delay))
    local coroutine_key = math.random()
    session.coroutine_key = coroutine_key
    coroutine.schedule(function () input_fish_command(coroutine_key) end, cast_delay)
end

local function stop_cast_attempts()
    session.coroutine_key = math.random()
end

local function send_fishing_action(stamina_percent, gold_arrow_chance, coroutine_key)
    if session.running and coroutine_key == session.coroutine_key then
        local player = windower.ffxi.get_player()
        windower.packets.inject_outgoing(0x110, string.pack('IIIHHI', 0xB10, player.id, stamina_percent, player.index, 3, gold_arrow_chance))
    end
end

local schedule_catch
do
    local function calculate_catch_delay(fishing_parameters)
        local catch_delay_tweak = math.max(settings.catch_delay_tweak, 1)
        local regen_per_second = (fishing_parameters[3] - 128) * 60 - fishing_parameters[1] / catch_delay_tweak
        local catch_delay = fishing_parameters[7] - 4
        if regen_per_second < 0 then
            catch_delay = math.min(math.abs(fishing_parameters[1] / regen_per_second), catch_delay)
        end
        return math.min(settings.catch_delay_max, math.max(settings.catch_delay_min, catch_delay))
    end

    function schedule_catch(fishing_parameters)
        local delay = calculate_catch_delay(fishing_parameters)
        message(string.format('catching in %d seconds', delay))
        local gold_arrow_chance = fishing_parameters[9]
        local coroutine_key = math.random()
        session.coroutine_key = coroutine_key
        coroutine.schedule(function () send_fishing_action(0, gold_arrow_chance, coroutine_key) end, delay)
    end
end

local function schedule_release()
    message(string.format('releasing in %d seconds', settings.release_delay))
    local coroutine_key = math.random()
    session.coroutine_key = coroutine_key
    coroutine.schedule(function () send_fishing_action(200, 0, coroutine_key) end, settings.release_delay)
end

local function start_fishing(catch_limit)
    if not session.running and windower.ffxi.get_player().status == 0 then
        session.running = true
        local coroutine_key = math.random()
        session.coroutine_key = coroutine_key
        session.catch_limit = tonumber(catch_limit) or 0
        if session.catch_limit > 0 then
            message(string.format('started automated fishing (catch limit = %d)', session.catch_limit), MESSAGE_WARN)
        else
            message('started automated fishing', MESSAGE_WARN)
        end
		if(settings.anti_gm.geofence.enabled) then
			set_geofence()
			message('[Anti-GM] No-hoe-check mode engaged.')
		end
		if(settings.anti_gm.dry_detection.enabled) then
			initialize_dry_detection()
			message('[Anti-GM] Dry-detection enabled.')
		end
        coroutine.schedule(function () input_fish_command(coroutine_key) end, 0)
    end
end

local identify_hooked_item
do
    local function make_uid(item, normal_mod, legendary_mod, size_mod)
        local stamina = item.stamina
        local arrow_duration = item.arrow_duration
        local arrow_frequency = item.arrow_frequency
        if item.count then
            local count_mod = 1 + 0.1 * (item.count - 1)
            stamina = math.floor(stamina * count_mod)
            arrow_duration = math.floor(arrow_duration * count_mod)
            arrow_frequency = math.floor(arrow_frequency * count_mod)
        end
        local size = item.size or 0
		--Bee: size mod is neither 0 nor 1 for shanger+ebisu.
        if size_mod == 0 and size == 1 then
            arrow_duration = math.max(arrow_duration - 1, 1)
            arrow_frequency = arrow_frequency + 2
        elseif size_mod == 1 and size == 0 then
            arrow_duration = math.max(arrow_duration - 2, 1)
            arrow_frequency = math.max(arrow_frequency - 1, 1)
        end
        local stamina_depletion = item.stamina_depletion
        if normal_mod and not item.legendary then
			--Bee: On retail this is floored prior to being multiplied by 20. On ASB, it is floored after multiplication by 20
            stamina_depletion = stamina_depletion * normal_mod / 100
        end
        legendary_mod = legendary_mod or normal_mod
        if legendary_mod and item.legendary then
			--Bee: On retail this is floored prior to being multiplied by 20. On ASB, it is floored after multiplication by 20
            stamina_depletion = stamina_depletion * legendary_mod / 100
        end
		--Bee: On ASB, this is floored after multiplication by 20. On horizon, they subtract 1.
		--Bee: As of 2023-10-28, they no longer subtract 1. 
		--Bee: Discovered on 2023-11-13, 1 is subtracted from some fish only when using ebisu. 
		local horizon_stamina_depletion = math.floor(stamina_depletion * 20)
		
		
        return {stamina, math.min(arrow_duration, 15), math.min(arrow_frequency, 15), horizon_stamina_depletion, size}
    end

    local item_by_rod_and_uid = {}

    local function find_item(stamina_base, fishing_parameters)
        local range_id = get_equipped_item_id('range')
        if not item_by_rod_and_uid[range_id] then
            local item_by_uid = {}
            local rod_modifiers = data.rod_modifiers_by_id[range_id]
            for i = 1, #data.item_fishing_parameters do
                local item = data.item_fishing_parameters[i]
                local uid_table = make_uid(item, unpack(rod_modifiers))
				--Bee: Universal parameter offset fix on Horizon XI
				--Adds both an item's parameters, and the parameters offset by 1.
				local uid_string1 = table.concat(uid_table, ',')
				if not item_by_uid[uid_string1] then item_by_uid[uid_string1] = {} end
				table.insert(item_by_uid[uid_string1], item)
				uid_table[4] = uid_table[4] - 1
				local uid_string2 = table.concat(uid_table, ',')
                if not item_by_uid[uid_string2] then item_by_uid[uid_string2] = {} end
				table.insert(item_by_uid[uid_string2], item)
            end
            item_by_rod_and_uid[range_id] = item_by_uid
            message('item uid cache updated: ' .. range_id, MESSAGE_DEBUG)
        end
        local uid = table.concat({stamina_base, fishing_parameters[2], fishing_parameters[4], fishing_parameters[5], fishing_parameters[8] % 2}, ',')
        return item_by_rod_and_uid[range_id][uid]
    end

    function identify_hooked_item(fishing_parameters)
        local continent = data.continent_by_zone[windower.ffxi.get_info().zone] or 1
        local identified = {}
        for i = 95, 105 do
            if fishing_parameters[1] % i == 0 then
                local item = find_item(math.floor(fishing_parameters[1] / i), fishing_parameters)
                if item then
                    for j = 1, #item do
                        if not item[j].continent or bit.band(item[j].continent, continent) ~= 0 then
                            table.insert(identified, item[j])
                        end
                    end
                end
            end
        end
        if #identified == 0 then
            table.insert(identified, data.unknown_item)
        end
        return identified
    end
end

windower.register_event('action', function (action)
    if session.running then
        local player_id = windower.ffxi.get_player().id
        for _, target in pairs(action.targets) do
            if target.id == player_id then stop_fishing('targeted by action') end
        end
    end
end)

windower.register_event('incoming chunk', function (id, original)
	if(settings.anti_gm.geofence.enabled) then
		check_geofence()
	end
	if id == 0x00A then --zone
		if(session.running and settings.anti_gm.geofence.enabled and session.geofence) then
			if(session.geofence.zone == windower.ffxi.get_info().zone) then
				on_geofence_break()
			else
				stop_fishing('Zoned')
			end
		elseif(session.running) then
			stop_fishing('Zoned')
		end
    elseif id == 0x00B then
        if string.byte(original, 5) == 1 then
            stop_fishing('log out')
        else
            stop_fishing('zone change')
        end
    elseif id == 0x017 then
        if string.byte(original, 6) % 2 == 1 and res.chat[string.byte(original, 1)] then
            stop_fishing('chat message from gm')
        end
	--status flags defined here: https://github.com/AirSkyBoat/AirSkyBoat/blob/3b961762066e259cbc42c62732ca86c2a6aea8a0/src/map/entities/baseentity.h#L4
    elseif id == 0x037 then
		local dry_detection_enabled = settings.anti_gm.dry_detection.enabled
        local player_status = windower.ffxi.get_player().status
        if session.player_status == player_status then return end
        message(string.format('player status update: %d, %d', player_status, string.byte(original, 75)), MESSAGE_DEBUG)
        if player_status == 58 or player_status == 61 then
            if session.running and session.catch_limit > 0 then
                session.catch_limit = session.catch_limit - 1
                if session.catch_limit > 0 then
                    message(string.format('remaining catch limit = %d', session.catch_limit))
                else
                    stop_fishing('catch limit')
                end
            end
        end
        if session.running then
			--idle
            if player_status == 0 and dry_detection_enabled then
				--reset dryness counter on restock
				if(should_reset_no_catch_count()) then
					message(
						string.format('Resetting no_catch_count (was %d)', session.dry_detection.no_catch_count), 
						MESSAGE_DEBUG
					)
					reset_no_catch_count()
				end
				if(session.dry_detection.last_cast_time) then
					message(
						string.format('Resetting last_cast_time (was %d:%d)', 
							math.floor(session.dry_detection.last_cast_time/60), 
								session.dry_detection.last_cast_time % 60
							), 
						MESSAGE_DEBUG
					)
				else
					message('Setting last cast time.')
				end
				session.dry_detection.last_cast_time = nil
				--check for dryness
				if(is_dry()) then
					message(
						string.format('Dryness detected! (%d no-catches in a row)', 
							session.dry_detection.no_catch_count
						),
						MESSAGE_ERROR
					)
					local delayed_cast_time = get_delay_until_restock()
					local next_restock = get_next_restock_vanadiel_time(windower.ffxi.get_info().time)
					schedule_delay_notifications(delayed_cast_time, next_restock)
					schedule_cast(delayed_cast_time)
				else
					schedule_cast(settings.recast_delay)
				end
			--idle
			elseif player_status == 0 then
				schedule_cast(settings.recast_delay)
			--rod in water and previously idle
			elseif player_status == 56 and session.player_status == 0 
					and dry_detection_enabled then
				session.dry_detection.last_cast_time = windower.ffxi.get_info().time
				message(
					string.format('Setting last cast time to %d:%d', 
						math.floor(session.dry_detection.last_cast_time/60), 
							session.dry_detection.last_cast_time % 60
						), 
					MESSAGE_DEBUG
				)
				stop_cast_attempts()
			--rod in water nothing on hook
            elseif player_status == 56 then
                stop_cast_attempts()
			--reeling back a catch
			elseif player_status == 58 then
				if(dry_detection_enabled) then
					reset_no_catch_count()
				end
				--table.insert(state.visualizer.catch_times, os.time())
			--reeling back without a catch
            elseif player_status == 62 and session.player_status ~= 58
					and settings.anti_gm.dry_detection.enabled then
				increment_no_catch_count()
				message(
					string.format('Incrementing no_catch_count (%d/%d)', 
						session.dry_detection.no_catch_count, 
						settings.anti_gm.dry_detection.no_catch_limit
					), 
					MESSAGE_DEBUG
				)
            elseif not (player_status >= 56 and player_status <= 62 or player_status == 0) then
                stop_fishing('invalid player status')
            end
        end
        session.player_status = player_status
    elseif id == 0x115 then
		--Stamina, arrow duration, regen, arrow frequency/delay, fish attack, miss regen, delay, size (1=big), special
        local fishing_parameters = {string.unpack(original, 'HHHHHHHHI', 5)}
        message(string.format('params: ' .. table.concat(fishing_parameters, ', ')), MESSAGE_DEBUG)
        if check_equipment() then
            local catch = false
            local identified = identify_hooked_item(fishing_parameters)
            for i = 1, #identified do
                local item = identified[i]
                if item.count then
                    message(string.format('hooked = %s x%d', item.name, item.count), MESSAGE_WARN)
                else
					if(item.name == 'unknown') then
						message(string.format('%s (%s)', item.name, table.concat(fishing_parameters, ', ')), MESSAGE_WARN)
					else
						message(string.format('hooked = %s', item.name), MESSAGE_WARN)
					end
                    
                end
                if session.running and not catch then
                    if session.item_by_id[item.id] then catch = true end
                end
            end
            if session.running then
                if catch then schedule_catch(fishing_parameters) else schedule_release() end
            end
        elseif session.running then
            stop_fishing('invalid equipment')
        else
            message('unable to identify hooked item (invalid equipment)', MESSAGE_ERROR)
        end
    end
end)

windower.register_event('outgoing chunk', function (id, original, _, injected)
    if id == 0x01A then
        local action_category = string.byte(original, 11)
        if action_category ~= 14 then stop_fishing('performed another action') end
    elseif id == 0x110 then
        local _, stamina_percent, _, action_type, gold_arrow_chance = string.unpack(original, 'IIHHI', 5)
        message('fishing action: ' .. table.concat({stamina_percent, action_type, gold_arrow_chance}, ', '), MESSAGE_DEBUG)
        if action_type == 3 then
            if stamina_percent == 300 then
                stop_fishing('fishing timed out')
            elseif not injected then
                stop_fishing('manual fishing action')
            end
        end
    end
end)

do
    local function command_add(item_name)
        if item_name == 'all' then
            command_add('all fish')
            command_add('all item')
            command_add('all bait')
        elseif item_name == 'all fish' then
            for name, id in pairs(data.fish_by_name) do
                session.item_by_id[id] = name
            end
            message('added all fishes to catch')
        elseif item_name == 'all item' then
            for name, id in pairs(data.item_by_name) do
                if id < 80000 then session.item_by_id[id] = name end
            end
            message('added all items to catch')
        elseif item_name == 'all bait' then
            for name, id in pairs(data.bait_by_name) do
                session.bait_by_id[id] = name
            end
            message('added all baits to use')
        elseif data.fish_by_name[item_name] then
            local item_id = data.fish_by_name[item_name]
            session.item_by_id[item_id] = item_name
            message(string.format('added fish to catch = %s (%d)', item_name, item_id))
        elseif data.item_by_name[item_name] then
            local item_id = data.item_by_name[item_name]
            session.item_by_id[item_id] = item_name
            message(string.format('added item to catch = %s (%d)', item_name, item_id))
        elseif data.bait_by_name[item_name] then
            local item_id = data.bait_by_name[item_name]
            session.bait_by_id[item_id] = item_name
            message(string.format('added bait to use = %s (%d)', item_name, item_id))
        else
            message('invalid fish, item or bait name', MESSAGE_ERROR)
        end
    end

    local function command_remove(item_name)
        local item_id = tonumber(item_name)
        item_id = item_id or data.fish_by_name[item_name]
        item_id = item_id or data.item_by_name[item_name]
        item_id = item_id or data.bait_by_name[item_name]
        if item_name == 'all' then
            command_remove('all fish')
            command_remove('all item')
            command_remove('all bait')
        elseif item_name == 'all fish' then
            for _, id in pairs(data.fish_by_name) do
                session.item_by_id[id] = nil
            end
            message('removed all fishes to catch')
        elseif item_name == 'all item' then
            for _, id in pairs(data.item_by_name) do
                session.item_by_id[id] = nil
            end
            message('removed all items to catch')
        elseif item_name == 'all bait' then
            session.bait_by_id = {}
            message('removed all baits to use')
        elseif session.item_by_id[item_id] then
            item_name = session.item_by_id[item_id]
            session.item_by_id[item_id] = nil
            if data.fish_by_name[item_name] then
                message(string.format('removed fish to catch = %s (%d)', item_name, item_id))
            else
                message(string.format('removed item to catch = %s (%d)', item_name, item_id))
            end
        elseif session.bait_by_id[item_id] then
            item_name = session.bait_by_id[item_id]
            session.bait_by_id[item_id] = nil
            message(string.format('removed bait to use = %s (%d)', item_name, item_id))
        else
            message('invalid fish, item or bait', MESSAGE_ERROR)
        end
    end

    local function command_list()
        for item_id, item_name in pairs(session.item_by_id) do
            if data.fish_by_name[item_name] then
                message(string.format('fish to catch = %s (%d)', item_name, item_id))
            else
                message(string.format('item to catch = %s (%d)', item_name, item_id))
            end
        end
        if not next(session.item_by_id) then
            message('nothing set to catch', MESSAGE_ERROR)
        end
        for item_id, item_name in pairs(session.bait_by_id) do
            message(string.format('bait to use = %s (%d)', item_name, item_id))
        end
        if not next(session.bait_by_id) then
            message('no bait set to use', MESSAGE_ERROR)
        end
    end
	
	local function set_catch_delay_max(value)
		settings.catch_delay_max = tonumber(value)
		message('Set \'catch_delay_max\' set to ' .. value, MESSAGE_INFO)
	end
	
	local function set_catch_delay_min(value)
		settings.catch_delay_min = tonumber(value)
		message('Set \'catch_delay_min\' set to ' .. value, MESSAGE_INFO)
	end
	
	local function set_catch_delay_tweak(value)
		settings.catch_delay_tweak = tonumber(value)
		message('Set \'catch_delay_tweak\' set to ' .. value, MESSAGE_INFO)
	end
    windower.register_event('addon command', function (command, ...)
        command = string.lower(command)
        local argument = string.lower(table.concat({...}, ' '))
        if #argument == 0 then argument = nil end
        if command == 'start' then
            start_fishing()
        elseif command == 'stop' then
            stop_fishing()
        elseif command == 'add' then
            command_add(argument)
        elseif command == 'remove' then
            command_remove(argument)
        elseif command == 'list' then
            command_list()
		elseif command == 'dismiss' then
			clear_alert()
		elseif command == 'catch_delay_max' then
			set_catch_delay_max(argument)
		elseif command == 'catch_delay_min' then
			set_catch_delay_min(argument)
		elseif command == 'catch_delay_tweak' then
			set_catch_delay_tweak(argument)
        end
    end)
end
