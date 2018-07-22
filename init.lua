--[[
=================================================================
Copyright (c) 2018 quater.
Licenced under the MIT licence. See LICENCE for more information.
=================================================================
--]]

--[[
  help book
]]
--[[
  type:
    open locked chest, locked door
    regenerate mana (by life, by stealing)
    regeneration (life)
    attack: fire, ice, lightning,
    motion: fast, slow, teleport
    inspect (player, locked chest)
    interfere with the cast
    'reset'/change the world seed
  specials:
    auto-regeneration
    auto-escape
]]
--[[
  properties:
    speed of cast
    speed of attack
    power of attack
    range
    duration
    random
    hp
    tick
    coordinates
]]
--[[
  rank:
    -1. Anti-magic (Demon) [00000000000]
    0. Destruction & Creation (Nature) [0000000000]
    1. Motion (Teleport, Fast, slow) [000000000]
    2. lightning (Lightning) [00000000]
    3. ice (Ice) [0000000]
    4. fire (Fire) [000000]
]]
--[[
  Experience system ?
  share encrypted book (known issue: memory)
  revoke encrypted spell
  hdbars: not tested
]]

magic = {}
magic.players = {}
magic.regeneration_timer = 0
magic.tick = 8

--[[
    DEFINITIONS OF CONSTANTS AND PROPERTIES
]]
local world = 'q'
local seed = 2

local hash = core.sha1
local hash_name = 'minetest.sha1'

local save_to_disk, read_disk

local rank = {
  ['Fire'] = 4,
  ['Ice'] = 3,
  ['Lightning'] = 2,
  ['Motion'] = 1,
  ['Nature'] = 0,
  ['Demon'] = -1
}
local rank_level = {
  ['Fire'] = string.rep('0', 6),
  ['Ice'] = string.rep('0', 7),
  ['Lightning'] = string.rep('0', 8),
  ['Motion'] = string.rep('0', 9),
  ['Nature'] = string.rep('0', 10),
  ['Demon'] = string.rep('0', 11),
}
local rank_settings = {}
rank_settings['Fire'] = {}
rank_settings['Fire']['regeneration'] = 1
rank_settings['Fire']['max_mana'] = 84
rank_settings['Ice'] = {}
rank_settings['Ice']['regeneration'] = 2
rank_settings['Ice']['max_mana'] = 88
rank_settings['Lightning'] = {}
rank_settings['Lightning']['regeneration'] = 4
rank_settings['Lightning']['max_mana'] = 92
rank_settings['Motion'] = {}
rank_settings['Motion']['regeneration'] = 8
rank_settings['Motion']['max_mana'] = 96
rank_settings['Nature'] = {}
rank_settings['Nature']['regeneration'] = 16
rank_settings['Nature']['max_mana'] = 100

local attack_properties = {}
attack_properties['cast_speed'] = 1
attack_properties['speed'] = 1
attack_properties['power'] = 1
attack_properties['range'] = 1

local motion_properties = {}
motion_properties['duration'] = 1
motion_properties['range'] = 1
motion_properties['speed'] = 1 -- fast or slow
motion_properties['coordinates'] = 1 -- relative coordinates

local inspection_properties = {}
inspection_properties['cast_speed'] = 1

local jamming_properties = {}
jamming_properties['cast_speed'] = 1
jamming_properties['random'] = 1
jamming_properties['range'] = 1

local healing_properties = {}
healing_properties['cast_speed'] = 1
healing_properties['tick'] = 1
healing_properties['hp'] = 1
healing_properties['duration'] = 1

local grant_rank, attack, motion, inspection, jamming, healing

--[[
    DEFINITIONS OF FUNCTIONS
]]
local cast_spell = function(itemstack, user, at)
  local meta = itemstack:get_meta()
  local data = meta:to_table().fields
  local lines = {}
  for line in data.text:gmatch('[^\n]+') do
    table.insert(lines, line)
  end
  if lines[1] == 'rank' then
    grant_rank(user, lines)
  elseif lines[1] == 'attack' then
    attack(user, lines)
  elseif lines[1] == 'motion' then
    motion(user, lines)
  elseif lines[1] == 'inspection' then
    inspection(user, lines, at)
  elseif lines[1] == 'jamming' then
    jamming(user, lines)
  elseif lines[1] == 'healing' then
    healing(user, lines)
  else
    -- not a spell or unknown spell
  end
end

save_to_disk = function()
  local file_path = core.get_worldpath() .. '/magic.mt'
  local file = io.open(file_path, 'w')
  local str = core.serialize(magic.players)
  if file then
    file:write(str)
    io.close(file)
  else
    core.log('error', '[magic] Failed to open file in ' .. file_path)
  end
end

read_disk = function()
  local file_path = core.get_worldpath() .. '/magic.mt'
  local file = io.open(file_path, 'r')
  if file then
    local players = core.deserialize(file:read() or '')
    if players then
      magic.players = players
    end
    io.close(file)
  end
end

grant_rank = function(user, lines)
  local level, w, name, ty, nonce = lines[2]:match('([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)')
  if name ~= user:get_player_name() then
    return
  end
  if rank[magic.players[name].rank] then
    return
  end
  if not rank[ty] then
    return
  end
  if rank_level[ty] ~= level then
    return
  end
  if w ~= world then
    return
  end
  local hash_str = hash(w .. name .. ty .. nonce)
  if hash_str:sub(1, #level) == string.rep('0', #level) then
    core.chat_send_player(name, 'The rank of ' .. ty .. ' has be granted to you')
    magic.players[name].rank = ty
    if ty ~= 'Demon' then
      magic.players[name].has_magic = true
      magic.players[name].mana = 0
      magic.players[name].max_mana = rank_settings[ty].max_mana
      magic.players[name].regeneration = rank_settings[ty].regeneration
      magic.hud_add(name)
    end
  end
end

attack = function(user, lines)
  local name = user:get_player_name()
  if not magic.players[name].has_magic then
    return
  end
  core.chat_send_player(name, 'Attack')
  local properties = {}
  for i = 2, 5 do
    local level, w, name, ty, nonce = lines[i]:match('([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)')
    if not name or not attack_properties[name] then
      return -- TODO: punish bad spell
    end
    local hash_str = hash(w .. name .. ty .. nonce)
    if hash_str:sub(1, #level) ~= string.rep('0', #level) then
      return -- TODO: punish bad spell
    end
    properties[name] = #level
  end
  local cast_speed, speed, power, range
  local sum = 0
  for k, v in pairs(properties) do
    sum = sum + v
    if k == 'cast_speed' then
      cast_speed = 8 / v - 1
      cast_speed = math.max(8 / v - 1, 0)
    elseif k == 'speed' then
      speed = v
    elseif k == 'power' then
      power = 15 / 14 * (v - 1) + 1 / 2
    elseif k == 'range' then
      range = 15 * (v - 1) + 10
    end
  end
  local mana = magic.players[user:get_player_name()].mana
  if mana - sum < 0 then
    return
  end
  magic.players[user:get_player_name()].mana = mana - sum
  core.chat_send_player(user:get_player_name(), 'cast speed: ' .. cast_speed .. ', speed: ' .. speed .. ', power: ' .. power .. ', range: ' .. range)
  if cast_speed == 0 then
    local pos = user:get_pos()
    pos.y = pos.y + 1.5
    local u = user:get_look_dir()
    u.x = speed * u.x;
    u.y = speed * u.y;
    u.z = speed * u.z;
    --[[
    pos.x = pos.x + u.x * 0.5
    pos.y = pos.y + u.y * 0.5
    pos.z = pos.z + u.z * 0.5
    -- ]]
    local obj = core.add_entity(pos, 'magic:ball')
    obj:setvelocity(u)
    local lua_entity = obj:get_luaentity()
    lua_entity.radius = range
    lua_entity.damage = power
  else
    core.after(cast_speed, function()
      local pos = user:get_pos()
      pos.y = pos.y + 1.5
      local u = user:get_look_dir()
      u.x = speed * u.x;
      u.y = speed * u.y;
      u.z = speed * u.z;
      --[[
      pos.x = pos.x + u.x * 0.5
      pos.y = pos.y + u.y * 0.5
      pos.z = pos.z + u.z * 0.5
      -- ]]
      local obj = core.add_entity(pos, 'magic:ball')
      obj:setvelocity(u)
      local lua_entity = obj:get_luaentity()
      lua_entity.radius = range
      lua_entity.damage = power
    end)
  end
end

motion = function(user, lines)
end

inspection = function(user, lines)
end

jamming = function(user, lines)
end

healing = function(user, lines)
end

if core.get_modpath('hudbard') then
  hb.register_hudbar('mana', 0xffffff, 'Mana')
  function magic.hud_update(name)
    local user = core.get_player_by_name(name)
    if player then
      hb.change_hudbar(user, 'mana', mana.players[name].mana,
        mana.players[name].max_mana)
    end
  end
  function magic.hud_remove(_)
  end
else
  function magic.mana_tostring(name)
    return 'Mana: ' .. magic.players[name].mana .. '/' .. magic.players[name].max_mana
  end
  function magic.hud_add(name)
    local user = core.get_player_by_name(name)
    local id = user:hud_add({
      hud_element_type = 'text',
      position = { x = 0.5, y = 1 },
      text = magic.mana_tostring(name),
      scale = { x = 0.5, y = 0 },
      alignment = { x = 1, y = 0 },
      direction = 1,
      number = 0xffffff,
      offset = { x = -262, y = -103 }
    })
    magic.players[name].hudid = id
    return id
  end
  function magic.hud_update(name)
    local user = core.get_player_by_name(name)
    user:hud_change(magic.players[name].hudid, 'text', magic.mana_tostring(name))
  end
  function magic.hud_remove(name)
    local user = core.get_player_by_name(name)
    user:hud_remove(magic.players[name].hudid)
  end
end

--[[
    EXECUCTED ONCE
]]
do
  read_disk()
end


--[[
    CORE FUNCTIONS
]]
core.override_item('default:book', {
  on_place = cast_spell,
  on_secondary_use = cast_spell,
})
core.override_item('default:book_written', {
  on_place = cast_spell,
  on_secondary_use = cast_spell,
})

core.register_entity('magic:ball', {
  --radius = 5,
  --damage = 5,
  --origin = { x = 0, y = 0, z = 0 },
  hp_max = 100,
  visual = 'sprite',
  visual_size = { x = 0.6, y = 0.6 },
  physical = false,
  --textures = { '' },
  on_activate = function(self, static_data)
    self.object:set_armor_groups({ immortal = 1 })
    self.object:set_properties({ textures = { 'mobs_fireball.png' }})
    self.object:set_properties({ visual_size = { x = 1, y = 1 }})
    self.origin = self.object:getpos()
    local table = core.deserialize(static_data)
    for k, v in pairs(table or {}) do
      self[k] = v
    end
  end,
  get_staticdata = function(self)
    local table = {}
    table.radius = self.radius
    table.damage = self.damage
    table.origin = self.origin
    return core.serialize(table)
  end,
  on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, direction)
    -- TODO: Demon sword
    return
  end,
  on_step = function(self, tick)
    local distance = 0
    local pos = self.object:getpos()
    distance = distance + math.pow(self.origin.x - pos.x, 2)
    distance = distance + math.pow(self.origin.y - pos.y, 2)
    distance = distance + math.pow(self.origin.z - pos.z, 2)
    distance = math.sqrt(distance)
    -- Safe zone
    if distance < 2 then
      return
    end
    -- Maximum distance
    if distance > self.radius then
      self.object:remove()
    end
    -- Check for collision
    local node_name = core.get_node(self.object:getpos()).name
    if node_name ~= 'air' and core.registered_nodes[node_name].walkable then
      self.object:remove()
      return
    end
    local objects = core.get_objects_inside_radius(pos, 1.5)
    local object
    if #objects > 1 then
      for _, obj in pairs(objects) do
        local p = obj:getpos()
        local d = 0
        d = d + math.pow(p.x - pos.x, 2)
        d = d + math.pow(p.y - pos.y, 2)
        d = d + math.pow(p.z - pos.z, 2)
        d = math.sqrt(d)
        local hp = obj:get_hp()
        hp = hp - self.damage
        if hp < 0 then
          hp = 0
        end
        obj:set_hp(hp)
      end
      self.object:remove()
    end
  end
})

core.register_on_respawnplayer(
function(user)
  if magic.players[user:get_player_name()].has_magic then
    magic.players[user:get_player_name()].mana = 0
  end
end)

core.register_on_joinplayer(
function(user)
  local name = user:get_player_name()
  local display = false
  if not magic.players[name] then
    magic.players[name] = {}
    magic.players[name].has_magic = false
    magic.players[name].rank = 'None'
  elseif magic.players[name].has_magic then
    display = true
  end
  if display then
    if core.get_modpath('hudbars') then
      hb.init_hudbar(user, 'mana', magic.players[name].mana,
        magic.players[name].max_mana)
    else
      magic.hud_add(name)
    end
  end
end)

core.register_on_leaveplayer(
function(user)
  magic.hud_remove(user:get_player_name())
  save_to_disk()
end)

core.register_on_shutdown(
function()
  save_to_disk()
end)

core.register_globalstep(
function(tick)
  magic.regeneration_timer = magic.regeneration_timer + tick
  if magic.regeneration_timer > magic.tick then
    magic.regeneration_timer = magic.regeneration_timer % magic.tick
    local players = core.get_connected_players()
    for _, player in ipairs(players) do
      local name = player:get_player_name()
      if magic.players[name].has_magic then
        if player:get_hp() > 0 then
          magic.players[name].mana = magic.players[name].mana
            + magic.players[name].regeneration
          if magic.players[name].mana > magic.players[name].max_mana then
            magic.players[name].mana = magic.players[name].max_mana
          end
          magic.hud_update(name)
        end
      end
    end
  end
end)

core.register_chatcommand('rank', {
  description = 'Describe your magic rank',
  func = function(name)
    core.chat_send_player(name, 'Your rank: ' .. magic.players[name].rank)
    return true
  end
})

print('[MOD] magicae loaded.')
