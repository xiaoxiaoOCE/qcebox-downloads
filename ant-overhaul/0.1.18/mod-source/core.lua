-- Pure ledger logic. No UObject access, filesystem access, or executable deserialization.
local M = { SCHEMA = 1, INT_MAX = 2147483647, PAGE_SIZE = 4 }
-- Shared by stock and supplementary pages. Counts, not historic prices, are stored.
M.PRICE_POLICY = { base = 1, multiplier = 1.10, cap = 300 }
local HEADER = "EOTU_ALL_ATTRIBUTES\t1"
local MAX_BYTES, MAX_RECORDS = 8 * 1024 * 1024, 100000
local plans = setmetatable({}, { __mode = "k" })

local function integer(v, min)
    return type(v) == "number" and v == v and v % 1 == 0 and v >= (min or 0) and v <= M.INT_MAX
end
local function ident(v, length)
    return type(v) == "string" and #v > 0 and #v <= (length or 128)
        and v:match("^[A-Za-z0-9][A-Za-z0-9_.:-]*$") ~= nil
end
local function fingerprint(v)
    return type(v) == "string" and #v == 129 and v:sub(65, 65) == ":"
        and v:sub(1, 64):match("^[0-9a-f]+$") ~= nil
        and v:sub(66):match("^[0-9a-f]+$") ~= nil
end
local function keys(t)
    local result = {}
    for k in pairs(t) do result[#result + 1] = k end
    table.sort(result)
    return result
end
local function decimal(value) return string.format("%.0f", value) end
local function clone(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = clone(v) end
    return out
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function exact_fields(t, allowed)
    for k in pairs(t) do if not allowed[k] then return false end end
    return true
end
local function group_valid(group)
    if type(group) ~= "table" then return false end
    local sum = 0
    for stat, count in pairs(group) do
        if not ident(stat, 64) or not integer(count, 1) then return false end
        sum = sum + count
        if sum > M.INT_MAX then return false end
    end
    return true
end
local function points_valid(points)
    if type(points) ~= "table" then return false end
    for species, group in pairs(points) do
        if not ident(species) or not group_valid(group) or next(group) == nil then return false end
    end
    return true
end
local function validate(state, stable)
    if type(state) ~= "table" or not exact_fields(state, { schema = true, revision = true, slots = true })
        or state.schema ~= M.SCHEMA or not integer(state.revision) or type(state.slots) ~= "table" then
        return nil, "invalid_state"
    end
    for slot, data in pairs(state.slots) do
        if not ident(slot, 64) or type(data) ~= "table"
            or not exact_fields(data, { anchor = true, points = true, snapshots = true })
            or not fingerprint(data.anchor) or not points_valid(data.points)
            or type(data.snapshots) ~= "table" or data.snapshots[data.anchor] == nil then
            return nil, "invalid_slot"
        end
        for fp, points in pairs(data.snapshots) do
            if not fingerprint(fp) or not points_valid(points) then return nil, "invalid_snapshot" end
        end
        if stable and not equal(data.points, data.snapshots[data.anchor]) then
            return nil, "native_save_required"
        end
    end
    return true
end
local function revision_available(state)
    if state.revision >= M.INT_MAX then return nil, "revision_overflow" end
    return true
end
local function slot_data(state, slot)
    local ok, err = validate(state)
    if not ok then return nil, err end
    if not ident(slot, 64) then return nil, "invalid_slot_id" end
    if state.slots[slot] == nil then return nil, "unknown_slot" end
    return state.slots[slot]
end

function M.new_state() return { schema = M.SCHEMA, revision = 0, slots = {} } end
function M.validate(state, require_saved) return validate(state, require_saved == true) end
function M.make_fingerprint(main_sha256, level_sha256)
    if type(main_sha256) ~= "string" or type(level_sha256) ~= "string" then return nil, "invalid_fingerprint" end
    local fp = main_sha256:lower() .. ":" .. level_sha256:lower()
    if not fingerprint(fp) then return nil, "invalid_fingerprint" end
    return fp
end

-- Structural validation for this build's PMOC compressed save container.
-- This checks complete block framing; the engine validates/decompresses payloads.
function M.validate_native_save(bytes)
    if type(bytes)=="string" and bytes:sub(1,4)=="GVAS" then
        local ok, complete = pcall(function()
            local offset=5
            local function take(n) assert(n>=0 and offset+n-1<=#bytes);offset=offset+n end
            local function i32() local n=string.unpack("<i4",bytes,offset);take(4);return n end
            local function str()
                local n=i32();assert(n~=0 and math.abs(n)<=65536)
                local count=n>0 and n or -2*n
                assert(offset+count-1<=#bytes)
                local s=bytes:sub(offset,offset+count-1);take(count)
                assert(s:sub(-1)=="\0")
                return n>0 and s:sub(1,-2) or "<wide>"
            end
            assert(i32()==2);i32();take(10);str()
            assert(i32()==3);local count=i32();assert(count>=0 and count<=4096);take(count*20);str()
            local simple={IntProperty=true,UInt32Property=true,Int64Property=true,UInt64Property=true,
                FloatProperty=true,DoubleProperty=true,StrProperty=true,NameProperty=true,TextProperty=true,
                ObjectProperty=true,SoftObjectProperty=true,ClassProperty=true,SoftClassProperty=true}
            while offset<=#bytes do
                local name=str()
                if name=="None" then return offset+3==#bytes and bytes:sub(offset)=="\0\0\0\0" end
                local kind=str();local size,index=i32(),i32();assert(size>=0 and index>=0)
                if kind=="StructProperty" then str();take(16)
                elseif kind=="BoolProperty" then take(1)
                elseif kind=="ByteProperty" or kind=="EnumProperty" or kind=="ArrayProperty" or kind=="SetProperty" then str()
                elseif kind=="MapProperty" then str();str()
                else assert(simple[kind],"unsupported save tag") end
                local guid=bytes:byte(offset);take(1);assert(guid==0 or guid==1)
                if guid==1 then take(16) end
                take(size)
            end
            return false
        end)
        if ok and complete then return true end
        return nil,"invalid_gvas_save"
    end
    if type(bytes) ~= "string" or #bytes < 54 or bytes:sub(1,4) ~= "PMOC" then return nil,"invalid_save_container" end
    local offset, blocks = 5, 0
    while offset <= #bytes do
        if #bytes - offset + 1 < 48 then return nil,"truncated_save_header" end
        local magic, chunk, total_compressed, total_raw, compressed, raw = string.unpack("<I8I8I8I8I8I8", bytes, offset)
        if magic ~= 0x9E2A83C1 or chunk < 1 or chunk > 64*1024*1024 or raw < 1 or raw > chunk
            or total_compressed ~= compressed or total_raw ~= raw or compressed < 2
            or compressed > #bytes - offset - 47 then return nil,"invalid_save_block" end
        local a,b=bytes:byte(offset+48,offset+49)
        if a%16~=8 or (a*256+b)%31~=0 then return nil,"invalid_save_compression" end
        offset=offset+48+compressed;blocks=blocks+1
    end
    if blocks==0 or offset~=#bytes+1 then return nil,"invalid_save_length" end
    return true
end

-- Explicitly enroll a previously untracked native save with zero extra points.
-- This cannot erase a slot that already has history.
function M.seed_slot(state, slot, fp)
    local ok, err = validate(state)
    if not ok then return nil, err end
    if not ident(slot, 64) then return nil, "invalid_slot_id" end
    if not fingerprint(fp) then return nil, "invalid_fingerprint" end
    if state.slots[slot] then return nil, "slot_exists" end
    ok, err = revision_available(state)
    if not ok then return nil, err end
    state.slots[slot] = { anchor = fp, points = {}, snapshots = { [fp] = {} } }
    state.revision = state.revision + 1
    return true
end

function M.get_points(state, slot, species, stat)
    local data, err = slot_data(state, slot)
    if not data then return nil, err end
    if not ident(species) or not ident(stat, 64) then return nil, "invalid_identity" end
    return (data.points[species] or {})[stat] or 0
end

function M.total_points(state, slot, species, native_total)
    local data, err = slot_data(state, slot)
    if not data then return nil, err end
    if not ident(species) or not integer(native_total) then return nil, "invalid_total" end
    local total = native_total
    for _, count in pairs(data.points[species] or {}) do
        total = total + count
        if total > M.INT_MAX then return nil, "point_overflow" end
    end
    return total
end

local costs, cap_index, cost_error
local function prepare_costs()
    if costs then return true end
    if cost_error then return nil, cost_error end
    if type(string.pack) ~= "function" or type(string.unpack) ~= "function" then
        cost_error = "float32_unavailable"
        return nil, cost_error
    end
    local function f32(v) return (string.unpack("<f", string.pack("<f", v))) end
    costs = {}
    local policy = M.PRICE_POLICY
    if not integer(policy.base, 1) or not integer(policy.cap, policy.base)
        or type(policy.multiplier) ~= "number" or policy.multiplier <= 1 or policy.multiplier > 2 then
        cost_error = "invalid_price_policy"; return nil, cost_error
    end
    local value, multiplier = f32(policy.base), f32(policy.multiplier)
    for n = 0, 100000 do
        -- The native nonnegative Round path uses float32(value + 0.5).
        local rounded = math.floor(f32(value + 0.5))
        if rounded >= policy.cap then costs[n] = policy.cap; cap_index = n; break end
        costs[n] = rounded
        value = f32(value * multiplier)
    end
    if cap_index == nil then costs = nil; cost_error = "cost_table_invalid"; return nil, cost_error end
    return true
end

function M.next_cost(total)
    if not integer(total) then return nil, "invalid_total" end
    local ok, err = prepare_costs()
    if not ok then return nil, err end
    return costs[math.min(total, cap_index)]
end

function M.cost_for(total, quantity)
    if not integer(total) or not integer(quantity, 1) then return nil, "invalid_quantity" end
    local ok, err = prepare_costs()
    if not ok then return nil, err end
    local sum = 0
    local last = total + quantity - 1
    for n = total, math.min(last, cap_index - 1) do
        sum = sum + costs[n]
        if sum > M.INT_MAX then return nil, "cost_overflow" end
    end
    local capped = math.max(0, last - math.max(total, cap_index) + 1)
    if capped > math.floor((M.INT_MAX - sum) / costs[cap_index]) then return nil, "cost_overflow" end
    sum = sum + capped * costs[cap_index]
    return sum
end

-- An unknown native save can be adopted only when this slot has never had any
-- supplementary points, including every historical snapshot. No ranks or money
-- are reconstructed or changed; nonempty histories must retain strict matching.
function M.rebind_empty_history(state, slot, fp)
    local data, err = slot_data(state, slot)
    if not data then return nil, err end
    if not fingerprint(fp) then return nil, "invalid_fingerprint" end
    if next(data.points) ~= nil then return nil, "nonempty_history" end
    for _, points in pairs(data.snapshots) do
        if next(points) ~= nil then return nil, "nonempty_history" end
    end
    return M.capture_snapshot(state, slot, fp)
end

function M.has_pending(pending, pending_spend)
    if pending == nil then pending = {} end
    if pending_spend == nil then pending_spend = 0 end
    if type(pending) ~= "table" or not integer(pending_spend) then return nil, "invalid_pending" end
    local any = pending_spend > 0
    for stat, count in pairs(pending) do
        if not ident(stat, 64) or not integer(count) then return nil, "invalid_pending" end
        any = any or count > 0
    end
    return any
end

function M.page(options, index, pending, pending_spend)
    local any, err = M.has_pending(pending, pending_spend)
    if any == nil then return nil, err end
    if any then return nil, "pending_purchase" end
    if type(options) ~= "table" or #options == 0 or not integer(index, 1) then return nil, "invalid_page" end
    local seen, count = {}, 0
    for key, stat in pairs(options) do
        if not integer(key, 1) or key > #options or not ident(stat, 64) or seen[stat] then return nil, "invalid_options" end
        seen[stat], count = true, count + 1
    end
    if count ~= #options then return nil, "invalid_options" end
    local page_count = math.ceil(count / M.PAGE_SIZE)
    if index > page_count then return nil, "invalid_page" end
    local items = {}
    for i = (index - 1) * M.PAGE_SIZE + 1, math.min(index * M.PAGE_SIZE, count) do items[#items + 1] = options[i] end
    return { index = index, count = page_count, items = items, total_options = count }
end

-- limits is also an explicit applicability whitelist: {Health = maxExtraPoints}.
-- Native fields/ranks stay outside this ledger and are never migrated.
function M.plan_purchase(state, request)
    if type(request) ~= "table" then return nil, "invalid_request" end
    local data, err = slot_data(state, request.slot)
    if not data then return nil, err end
    if not ident(request.species) or not integer(request.native_total) or not integer(request.balance)
        or type(request.pending) ~= "table" or type(request.limits) ~= "table" then return nil, "invalid_request" end
    local total
    total, err = M.total_points(state, request.slot, request.species, request.native_total)
    if not total then return nil, err end
    local current = data.points[request.species] or {}
    local deltas, quantity, after = {}, 0, clone(current)
    for stat, count in pairs(request.pending) do
        if not ident(stat, 64) or not integer(count) then return nil, "invalid_pending" end
        if count > 0 then
            local cap = request.limits[stat]
            if not integer(cap) then return nil, "stat_not_allowed" end
            local next_value = (current[stat] or 0) + count
            if next_value > M.INT_MAX then return nil, "point_overflow" end
            if next_value > cap then return nil, "stat_cap" end
            quantity = quantity + count
            if quantity > M.INT_MAX then return nil, "point_overflow" end
            deltas[stat], after[stat] = count, next_value
        end
    end
    if quantity == 0 then return nil, "empty_purchase" end
    if total + quantity > M.INT_MAX then return nil, "point_overflow" end
    local price
    price, err = M.cost_for(total, quantity)
    if not price then return nil, err end
    if request.balance < price then return nil, "insufficient_funds" end
    local ok
    ok, err = revision_available(state)
    if not ok then return nil, err end
    local plan = {
        slot = request.slot, species = request.species, revision = state.revision, anchor = data.anchor,
        native_total = request.native_total, total_before = total, quantity = quantity,
        cost = price, balance = request.balance, deltas = deltas, points_before = clone(current), points_after = after
    }
    plans[plan] = { state = state, expected = clone(plan), consumed = false }
    return plan
end

-- Receipt values must be observed around the successful native spend call.
-- No native refund, disk write, or game attribute change happens here.
function M.commit_purchase(state, plan, receipt)
    local registered = type(plan) == "table" and plans[plan] or nil
    if not registered or registered.state ~= state then return nil, "unknown_plan" end
    if registered.consumed then return nil, "plan_consumed" end
    if not equal(plan, registered.expected) then return nil, "plan_changed" end
    local expected = registered.expected
    local data, err = slot_data(state, expected.slot)
    if not data then return nil, err end
    if state.revision ~= expected.revision or data.anchor ~= expected.anchor
        or not equal(data.points[expected.species] or {}, expected.points_before) then return nil, "stale_plan" end
    if type(receipt) ~= "table" or receipt.paid ~= true
        or not integer(receipt.before) or not integer(receipt.after) or not integer(receipt.native_total)
        or receipt.before ~= expected.balance or receipt.after ~= receipt.before - expected.cost
        or receipt.native_total ~= expected.native_total then return nil, "payment_mismatch" end
    local ok
    ok, err = revision_available(state)
    if not ok then return nil, err end
    data.points[expected.species] = clone(expected.points_after)
    state.revision = state.revision + 1
    registered.consumed = true
    return true
end

-- Call only after native SaveFormicarium finished successfully, with hashes
-- of the completed main and level saves. Never infer this from an attempted save.
function M.capture_snapshot(state, slot, fp)
    local data, err = slot_data(state, slot)
    if not data then return nil, err end
    if not fingerprint(fp) then return nil, "invalid_fingerprint" end
    local existing = data.snapshots[fp]
    if existing and not equal(existing, data.points) then return nil, "fingerprint_collision" end
    if data.anchor == fp and existing and equal(existing, data.points) then return true end
    local ok
    ok, err = revision_available(state)
    if not ok then return nil, err end
    data.snapshots[fp] = clone(data.points)
    data.anchor = fp
    state.revision = state.revision + 1
    return true
end

-- Called on native load. Unknown fingerprints fail closed rather than lending
-- a newer ledger to an older save. An intentional rollback discards live drafts.
function M.restore_snapshot(state, slot, fp)
    local data, err = slot_data(state, slot)
    if not data then return nil, err end
    if not fingerprint(fp) then return nil, "invalid_fingerprint" end
    local snapshot = data.snapshots[fp]
    if not snapshot then return nil, "unknown_fingerprint" end
    local ok
    ok, err = revision_available(state)
    if not ok then return nil, err end
    data.points = clone(snapshot)
    data.anchor = fp
    state.revision = state.revision + 1
    return true
end

function M.encode(state)
    local ok, err = validate(state, true)
    if not ok then return nil, err end
    local lines = { HEADER, "REV\t" .. decimal(state.revision) }
    for _, slot in ipairs(keys(state.slots)) do
        local data = state.slots[slot]
        lines[#lines + 1] = table.concat({ "SLOT", slot, data.anchor }, "\t")
        for _, species in ipairs(keys(data.points)) do
            for _, stat in ipairs(keys(data.points[species])) do
                lines[#lines + 1] = table.concat({ "POINT", slot, species, stat, decimal(data.points[species][stat]) }, "\t")
            end
        end
        for _, fp in ipairs(keys(data.snapshots)) do
            lines[#lines + 1] = table.concat({ "SNAP", slot, fp }, "\t")
            for _, species in ipairs(keys(data.snapshots[fp])) do
                for _, stat in ipairs(keys(data.snapshots[fp][species])) do
                    lines[#lines + 1] = table.concat({ "SNAPPOINT", slot, fp, species, stat, decimal(data.snapshots[fp][species][stat]) }, "\t")
                end
            end
        end
    end
    if #lines > MAX_RECORDS then return nil, "ledger_too_large" end
    local text = table.concat(lines, "\n") .. "\n"
    if #text > MAX_BYTES then return nil, "ledger_too_large" end
    return text
end

local function parse_int(value, min)
    if type(value) ~= "string" or #value > 10
        or not (value == "0" or value:match("^[1-9][0-9]*$")) then return nil end
    local n = tonumber(value)
    return integer(n, min) and n or nil
end
local function fields(line)
    local out = {}
    for value in (line .. "\t"):gmatch("(.-)\t") do out[#out + 1] = value end
    return out
end
local function insert_point(points, species, stat, raw_count)
    local count = parse_int(raw_count, 1)
    if not ident(species) or not ident(stat, 64) or not count then return nil, "invalid_point_record" end
    points[species] = points[species] or {}
    if points[species][stat] ~= nil then return nil, "duplicate_record" end
    points[species][stat] = count
    return true
end

function M.decode(text)
    if type(text) ~= "string" or #text > MAX_BYTES then return nil, "invalid_ledger_text" end
    text = text:gsub("\r\n", "\n")
    if text:find("\r", 1, true) or text:find("\0", 1, true) or text:sub(-1) ~= "\n" then return nil, "invalid_ledger_text" end
    local state, count, saw_revision = M.new_state(), 0, false
    for line in text:gmatch("([^\n]*)\n") do
        count = count + 1
        if count > MAX_RECORDS then return nil, "ledger_too_large" end
        if count == 1 then
            if line ~= HEADER then return nil, "unsupported_schema" end
        else
            local f, ok, err = fields(line)
            if f[1] == "REV" and #f == 2 and not saw_revision and count == 2 then
                local revision = parse_int(f[2])
                if revision == nil then return nil, "invalid_revision" end
                state.revision, saw_revision = revision, true
            elseif not saw_revision then return nil, "missing_revision"
            elseif f[1] == "SLOT" and #f == 3 then
                if not ident(f[2], 64) or not fingerprint(f[3]) then return nil, "invalid_slot_record" end
                if state.slots[f[2]] then return nil, "duplicate_record" end
                state.slots[f[2]] = { anchor = f[3], points = {}, snapshots = {} }
            elseif f[1] == "POINT" and #f == 5 then
                local data = state.slots[f[2]]
                if not data then return nil, "unknown_slot" end
                ok, err = insert_point(data.points, f[3], f[4], f[5])
                if not ok then return nil, err end
            elseif f[1] == "SNAP" and #f == 3 then
                local data = state.slots[f[2]]
                if not data or not fingerprint(f[3]) then return nil, "invalid_snapshot_record" end
                if data.snapshots[f[3]] then return nil, "duplicate_record" end
                data.snapshots[f[3]] = {}
            elseif f[1] == "SNAPPOINT" and #f == 6 then
                local data = state.slots[f[2]]
                if not data or not data.snapshots[f[3]] then return nil, "invalid_snapshot_record" end
                ok, err = insert_point(data.snapshots[f[3]], f[4], f[5], f[6])
                if not ok then return nil, err end
            else return nil, "invalid_record" end
        end
    end
    if count < 2 or not saw_revision then return nil, "missing_revision" end
    local ok, err = validate(state, true)
    if not ok then return nil, err end
    return state
end

-- Injected closures: io.read() -> bytes; io.atomic_write(bytes) -> true.
-- The implementation of atomic replacement/backups belongs to the integration.
function M.load(io_adapter)
    if type(io_adapter) ~= "table" or type(io_adapter.read) ~= "function" then return nil, "invalid_io" end
    local ok, text = pcall(io_adapter.read)
    if not ok or type(text) ~= "string" then return nil, "io_read_failed" end
    return M.decode(text)
end
function M.save(state, io_adapter)
    if type(io_adapter) ~= "table" or type(io_adapter.atomic_write) ~= "function" then return nil, "invalid_io" end
    local text, err = M.encode(state)
    if not text then return nil, err end
    local ok, written = pcall(io_adapter.atomic_write, text)
    if not ok or written ~= true then return nil, "io_write_failed" end
    return true
end

return M
