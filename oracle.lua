-- Headless Path of Building as a reference calculator for poe-lib.
-- Reads JSON lines {"name": "...", "xml": "<PathOfBuilding>..."} on stdin and
-- prints one line per build: "ORACLE\t" .. JSON {"name", "output", "error"},
-- where output is build.calcsTab.mainOutput (numbers, booleans, strings).
-- With "tabulate": ["Stat", ...] in the input, "tabulate" lists the player's
-- mods for those stats: {type, value, source}.
-- Run from PoB's src directory (see run.sh); PoB prints its own logs too,
-- so consumers keep only the ORACLE lines.
dofile("HeadlessWrapper.lua")
local dkjson = require "dkjson"

-- HeadlessWrapper's Inflate is a stub returning "". PoB needs it for the
-- compressed timeless jewel data, so bind zlib through LuaJIT's FFI.
local ffi = require "ffi"
ffi.cdef[[
typedef struct z_stream_s {
	const unsigned char *next_in; unsigned int avail_in; unsigned long total_in;
	unsigned char *next_out; unsigned int avail_out; unsigned long total_out;
	const char *msg; void *state; void *zalloc; void *zfree; void *opaque;
	int data_type; unsigned long adler; unsigned long reserved;
} z_stream;
int inflateInit2_(z_stream *strm, int windowBits, const char *version, int stream_size);
int inflate(z_stream *strm, int flush);
int inflateEnd(z_stream *strm);
const char *zlibVersion(void);
]]
local zlib = ffi.load("libz.so.1") -- alpine ships only the versioned name
function Inflate(data)
	if not data or #data == 0 then
		return nil, "no data"
	end
	local strm = ffi.new("z_stream")
	-- 15 + 32: zlib or gzip header, detected automatically
	if zlib.inflateInit2_(strm, 15 + 32, zlib.zlibVersion(), ffi.sizeof(strm)) ~= 0 then
		return nil, "inflateInit2 failed"
	end
	local input = ffi.new("unsigned char[?]", #data)
	ffi.copy(input, data, #data)
	strm.next_in, strm.avail_in = input, #data
	local chunk = 1048576
	local buf = ffi.new("unsigned char[?]", chunk)
	local parts = {}
	while true do
		strm.next_out, strm.avail_out = buf, chunk
		local rc = zlib.inflate(strm, 0)
		parts[#parts + 1] = ffi.string(buf, chunk - strm.avail_out)
		if rc == 1 then break end -- Z_STREAM_END
		if rc ~= 0 then
			zlib.inflateEnd(strm)
			return nil, "inflate failed: " .. rc
		end
	end
	zlib.inflateEnd(strm)
	return table.concat(parts)
end

local function plain(output)
	local out = {}
	for k, v in pairs(output) do
		local t = type(v)
		if (t == "number" and v == v and v ~= math.huge and v ~= -math.huge) or t == "boolean" or t == "string" then
			out[k] = v
		end
	end
	return out
end

for line in io.lines() do
	if line:match("%S") then
		local input = dkjson.decode(line)
		local result = { name = input and input.name }
		local ok, err = pcall(function()
			loadBuildFromXML(input.xml, input.name)
			result.output = plain(build.calcsTab.mainOutput)
			-- Optional: {"tabulate": ["Dex", ...]} lists the player's mods per
			-- stat (ModStore:Tabulate with no cfg) for debugging differences.
			-- Optional: {"allocNodes": true} lists the passive node ids PoB
			-- keeps allocated after loading (it drops unconnected ones).
			if input.allocNodes then
				result.allocNodes = {}
				for id in pairs(build.spec.allocNodes) do
					result.allocNodes[#result.allocNodes + 1] = id
				end
				table.sort(result.allocNodes)
			end
			-- Optional: {"nodesInRadius": [[socketId, radiusIndex], ...]} lists
			-- the tree nodes PoB counts in that jewel radius.
			if input.nodesInRadius then
				result.nodesInRadius = {}
				for _, q in ipairs(input.nodesInRadius) do
					local ids = {}
					local socket = build.spec.tree.nodes[q[1]]
					for id in pairs(socket and socket.nodesInRadius and socket.nodesInRadius[q[2]] or {}) do
						ids[#ids + 1] = id
					end
					table.sort(ids)
					result.nodesInRadius[#result.nodesInRadius + 1] = ids
				end
			end
			-- Optional: {"conditions": true} lists the player's true conditions
			-- and non-zero multipliers after the calculation.
			if input.conditions then
				local modDB = build.calcsTab.mainEnv.player.modDB
				result.conditions, result.multipliers = {}, {}
				for k, v in pairs(modDB.conditions) do
					if v == true then result.conditions[#result.conditions + 1] = k end
				end
				table.sort(result.conditions)
				for k, v in pairs(modDB.multipliers) do
					if type(v) == "number" and v ~= 0 then result.multipliers[k] = v end
				end
			end
			-- Optional: {"skills": true} lists the player's active skills: level,
			-- quality, buffs, and the aura effect rows of each skill's mod list.
			if input.skills then
				result.skills = {}
				local names = { "AuraEffect", "BuffEffect", "BuffEffectOnSelf", "AuraEffectOnSelf", "AuraBuffEffect", "SkillAuraEffectOnSelf" }
				for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
					local e = {
						name = s.activeEffect.grantedEffect.name,
						level = s.activeEffect.level,
						quality = s.activeEffect.quality,
						hasGemData = s.activeEffect.gemData ~= nil,
						srcLevel = s.activeEffect.srcInstance and s.activeEffect.srcInstance.level,
						disabled = s.skillFlags and s.skillFlags.disable and true or false,
						buffs = {},
						rows = {},
					}
					for _, b in ipairs(s.buffList or {}) do
						e.buffs[#e.buffs + 1] = b.type .. ":" .. b.name
						if input.buffMods then
							for _, m in ipairs(b.modList or {}) do
								e.buffs[#e.buffs + 1] = "  " .. m.name .. " " .. m.type .. " " .. tostring(m.value) .. " " .. tostring(m.source)
							end
						end
					end
					if s.skillModList and s.skillCfg then
						e.auraInc = s.skillModList:Sum("INC", s.skillCfg, unpack(names))
						e.auraMore = s.skillModList:More(s.skillCfg, unpack(names))
						for _, row in ipairs(s.skillModList:Tabulate("INC", s.skillCfg, unpack(names))) do
							e.rows[#e.rows + 1] = { name = row.mod.name, value = row.value, source = row.mod.source }
						end
					end
					result.skills[#result.skills + 1] = e
				end
			end
			-- Optional: {"itemArmour": true} lists armourData of the player's
			-- equipped items by slot.
			if input.itemArmour then
				result.itemArmour = {}
				for slot, item in pairs(build.calcsTab.mainEnv.player.itemList) do
					if item and item.armourData then
						result.itemArmour[slot] = { name = item.name, data = plain(item.armourData) }
					end
				end
			end
			-- Optional: {"skillTabulate": ["Stat", ...]} lists the player main
			-- skill's mods (weapon1Cfg or skillCfg) and the enemy's
			-- ("Enemy:<Stat>"), plus output.MainHand/OffHand and the skill flags.
			if input.skillTabulate then
				local o = build.calcsTab.mainOutput
				local ms = build.calcsTab.mainEnv.player.mainSkill
				result.mainSkill = ms.activeEffect.grantedEffect.name
				result.mainHand = type(o.MainHand) == "table" and plain(o.MainHand) or nil
				result.offHand = type(o.OffHand) == "table" and plain(o.OffHand) or nil
				result.skillFlags = plain(ms.skillFlags or {})
				result.skillData = plain(ms.skillData or {})
				result.effects = {}
				for _, e in ipairs(ms.effectList or {}) do
					result.effects[#result.effects + 1] = e.grantedEffect.name .. " L" .. tostring(e.level) .. " Q" .. tostring(e.quality)
				end
				result.skillTabulate = {}
				local cfg = ms.weapon1Cfg or ms.skillCfg
				for _, stat in ipairs(input.skillTabulate) do
					local db, name = ms.skillModList, stat
					if stat:sub(1, 6) == "Enemy:" then
						db, name = build.calcsTab.mainEnv.enemyDB, stat:sub(7)
					end
					local rows = {}
					for _, row in ipairs(db:Tabulate(nil, cfg, name)) do
						rows[#rows + 1] = { type = row.mod.type, value = type(row.value) == "number" and row.value or tostring(row.value), source = row.mod.source }
					end
					result.skillTabulate[stat] = rows
				end
			end
			-- Optional: {"breakdown": ["Physical", ...]} returns the CALCS mode
			-- breakdown of the player's main skill per hand (MainHand/OffHand)
			-- and at the top level, as nested tables of strings and numbers.
			if input.breakdown then
				local function deep(v, depth)
					local t = type(v)
					if t == "number" then
						return (v == v and v ~= math.huge and v ~= -math.huge) and v or tostring(v)
					elseif t == "string" or t == "boolean" then
						return v
					elseif t == "table" and depth < 6 then
						local o = {}
						for k, x in pairs(v) do
							o[tostring(k)] = deep(x, depth + 1)
						end
						return o
					end
					return nil
				end
				-- Point the Calcs tab at the main skill (it keeps its own choice).
				local g = build.skillsTab.socketGroupList[build.mainSocketGroup]
				build.calcsTab.input.skill_number = build.mainSocketGroup
				if g then
					g.mainActiveSkillCalcs = g.mainActiveSkill
					for _, gem in ipairs(g.gemList or {}) do
						for _, f in ipairs({ "skillPart", "skillStageCount", "skillMineCount", "skillMinion", "skillMinionItemSet", "skillMinionSkill" }) do
							gem[f .. "Calcs"] = gem[f]
						end
					end
				end
				build.calcsTab:BuildOutput()
				local bd = build.calcsTab.calcsEnv.player.breakdown or {}
				result.breakdown = {}
				for _, where in ipairs({ "MainHand", "OffHand", "" }) do
					local src = where == "" and bd or bd[where]
					if src then
						local o = {}
						for _, name in ipairs(input.breakdown) do
							o[name] = deep(src[name], 0)
						end
						result.breakdown[where == "" and "Top" or where] = o
					end
				end
			end
			-- Optional: {"minions": true} recalculates with each socket group's
			-- minion skills as the main skill and lists output.Minion for each.
			if input.minions then
				result.minions = {}
				local origGroup = build.mainSocketGroup
				for i, group in ipairs(build.skillsTab.socketGroupList) do
					local origSkill = group.mainActiveSkill
					for j, skill in ipairs(group.displaySkillList or {}) do
						if skill.minion or (skill.activeEffect and skill.activeEffect.grantedEffect.minionList) then
							build.mainSocketGroup, group.mainActiveSkill = i, j
							build.calcsTab:BuildOutput()
							local o = build.calcsTab.mainOutput.Minion
							if o then
								local main = build.calcsTab.mainEnv.player.mainSkill
								result.minions[#result.minions + 1] = {
									group = i, skill = j,
									name = main.activeEffect.grantedEffect.name,
									minion = main.minion and main.minion.minionData and main.minion.minionData.name,
									output = plain(o),
									tabulate = {},
								}
								local entry = result.minions[#result.minions]
								entry.mainHand = type(o.MainHand) == "table" and plain(o.MainHand) or nil
								local ms = build.calcsTab.mainEnv.minion.mainSkill
								entry.minionSkill = ms and ms.activeEffect.grantedEffect.name
								-- Optional: {"minionSkillTabulate": ["Stat", ...]} lists the
								-- minion main skill's mods (its skill cfg) for those stats.
								entry.skillTabulate = {}
								for _, stat in ipairs(input.minionSkillTabulate or {}) do
									local rows = {}
									local cfg = ms.weapon1Cfg or ms.skillCfg
									for _, row in ipairs(ms.skillModList:Tabulate(nil, cfg, stat)) do
										rows[#rows + 1] = { type = row.mod.type, value = type(row.value) == "number" and row.value or tostring(row.value), source = row.mod.source }
									end
									entry.skillTabulate[stat] = rows
								end
								-- Optional: {"minionEnemyTabulate": ["Stat", ...]} lists the
								-- enemy's mods in this calculation.
								entry.enemyTabulate = {}
								for _, stat in ipairs(input.minionEnemyTabulate or {}) do
									local rows = {}
									for _, row in ipairs(build.calcsTab.mainEnv.enemyDB:Tabulate(nil, ms and (ms.weapon1Cfg or ms.skillCfg), stat)) do
										rows[#rows + 1] = { type = row.mod.type, value = type(row.value) == "number" and row.value or tostring(row.value), source = row.mod.source }
									end
									entry.enemyTabulate[stat] = rows
								end
								-- Optional: {"minionTabulate": ["Stat", ...]} lists the
								-- minion's mods for those stats.
								for _, stat in ipairs(input.minionTabulate or {}) do
									local rows = {}
									for _, row in ipairs(build.calcsTab.mainEnv.minion.modDB:Tabulate(nil, nil, stat)) do
										rows[#rows + 1] = {
											type = row.mod.type,
											value = type(row.value) == "number" and row.value or tostring(row.value),
											source = row.mod.source,
										}
									end
									result.minions[#result.minions].tabulate[stat] = rows
								end
							end
						end
					end
					group.mainActiveSkill = origSkill
				end
				build.mainSocketGroup = origGroup
				build.calcsTab:BuildOutput()
			end
			if input.tabulate then
				result.tabulate = {}
				local modDB = build.calcsTab.mainEnv.player.modDB
				for _, stat in ipairs(input.tabulate) do
					local rows = {}
					-- "Enemy:<Stat>" tabulates the enemy's mods.
					local db, name = modDB, stat
					if stat:sub(1, 6) == "Enemy:" then
						db, name = build.calcsTab.mainEnv.enemy.modDB, stat:sub(7)
					end
					for _, row in ipairs(db:Tabulate(nil, nil, name)) do
						rows[#rows + 1] = {
							type = row.mod.type,
							value = type(row.value) == "number" and row.value or tostring(row.value),
							source = row.mod.source,
						}
					end
					result.tabulate[stat] = rows
				end
			end
		end)
		if not ok then
			result.error = tostring(err)
		end
		io.write("ORACLE\t", dkjson.encode(result), "\n")
		io.flush()
	end
end
