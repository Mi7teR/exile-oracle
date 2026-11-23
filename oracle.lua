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
			if input.tabulate then
				result.tabulate = {}
				local modDB = build.calcsTab.mainEnv.player.modDB
				for _, stat in ipairs(input.tabulate) do
					local rows = {}
					for _, row in ipairs(modDB:Tabulate(nil, nil, stat)) do
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
