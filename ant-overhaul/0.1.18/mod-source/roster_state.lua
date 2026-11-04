-- Pure persistence for story-roster choices. Native save creation and filesystem
-- ownership belong to the adapter; this module never loads code or touches IO.
local M = {schema=1}
local HEADER = "EAA_STORY_ROSTER_V1"
local MAX_RECORDS, MAX_FIELDS, MAX_BYTES = 1024, 128, 4194304
local RECORD_KEYS = {kind=true,native_slot=true,fingerprint=true,campaign_slot=true,mission_key=true,selectedIds=true,skillOverrides=true,variantOverrides=true,customSkills=true}
local QUERY_KEYS = {kind=true,native_slot=true,fingerprint=true,campaign_slot=true,mission_key=true}
local CUSTOM_OPTIONS = {
    TrapjawAnt={left={none=true,recovery=true,invulnerable=true},right={none=true,evasion=true,reward=true}},
    SlaveMaker={left={none=true,special_master=true,follow_step=true},right={none=true,overseer_drill=true,overseer_haul=true}},
}

local function plain(value)
    return type(value)=="table" and getmetatable(value)==nil
end
local function clone(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=clone(item) end; return result
end
local function only_keys(value, allowed)
    if not plain(value) then return false end
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end
local function name(value, maximum)
    return type(value)=="string" and #value>0 and #value<=maximum and value:match("^[A-Za-z0-9_-]+$")~=nil
end
local function mission(value)
    return type(value)=="string" and #value>0 and #value<=200
        and value:match("^[A-Za-z0-9_./-]+$")~=nil and not value:find("..",1,true)
end
local function fingerprint(value)
    return type(value)=="string" and #value==64 and value:match("^[a-f0-9]+$")~=nil
end
local function key_of(record)
    return record.kind..":"..record.native_slot..":"..record.fingerprint
end
local function identity(record)
    if record.kind~="save" and record.kind~="setup" then return nil,"invalid_kind" end
    if not name(record.native_slot,96) then return nil,"invalid_native_slot" end
    if not name(record.campaign_slot,96) then return nil,"invalid_campaign_slot" end
    if not mission(record.mission_key) then return nil,"invalid_mission_key" end
    if not fingerprint(record.fingerprint) then return nil,"invalid_fingerprint" end
    return true
end
local function allowlist(value)
    if not plain(value) then return nil end
    local count=0
    for key,item in pairs(value) do
        count=count+1
        if count>MAX_FIELDS or not name(key,96) or item~=true then return nil end
    end
    return true
end
local function valid_policy(policy)
    if not plain(policy) or not allowlist(policy.ids) or not allowlist(policy.skills) then return nil end
    if policy.variants~=nil then
        if not plain(policy.variants) then return nil end
        local count=0
        for field,owner in pairs(policy.variants) do
            count=count+1
            if count>MAX_FIELDS or not name(field,96) or not name(owner,96)
                or not policy.ids[owner] or policy.skills[field] then return nil end
        end
    end
    if policy.pairs==nil then return true end
    if not plain(policy.pairs) or #policy.pairs>MAX_FIELDS/2 then return nil end
    local count,seen=0,{}
    for index,pair in pairs(policy.pairs) do
        count=count+1
        if type(index)~="number" or index%1~=0 or index<1 or index>#policy.pairs
            or not only_keys(pair,{[1]=true,[2]=true}) or not policy.skills[pair[1]] or not policy.skills[pair[2]]
            or pair[1]==pair[2] or seen[pair[1]] or seen[pair[2]] then return nil end
        seen[pair[1]],seen[pair[2]]=true,true
    end
    return count==#policy.pairs
end
local function bool_map(value, allowed, selected)
    if not plain(value) then return nil,"invalid_selection_map" end
    local count=0
    for key,item in pairs(value) do
        count=count+1
        if count>MAX_FIELDS then return nil,"selection_too_large" end
        if not allowed[key] then return nil,"unknown_selection_field" end
        if type(item)~="boolean" or (selected and item~=true) then return nil,"invalid_selection_value" end
    end
    return true
end
-- Mod-only skills never enter the native skill flag allowlist or FColonyData.
local function custom_skills(value,policy)
    if value==nil then return {} end
    if not only_keys(value,CUSTOM_OPTIONS) then return nil,"invalid_custom_skills" end
    local out={}
    for id,row in pairs(value) do
        if not policy.ids[id] or not only_keys(row,{left=true,right=true}) then return nil,"invalid_custom_skill_pair" end
        local options=CUSTOM_OPTIONS[id]
        out[id]={}
        for _,side in ipairs({"left","right"}) do
            local choice=row[side] or "none"
            if not options[side][choice] then return nil,"unknown_custom_skill" end
            out[id][side]=choice
        end
    end
    return out
end
local function equal(left,right)
    if type(left)~=type(right) then return false end
    if type(left)~="table" then return left==right end
    for key,item in pairs(left) do if not equal(item,right[key]) then return false end end
    for key in pairs(right) do if left[key]==nil then return false end end
    return true
end

function M.new() return {schema=1,records={}} end

-- The caller supplies catalog data. No implicit module loading or cached policy.
function M.policy_from_catalog(catalog)
    if not plain(catalog) or not plain(catalog.by_id) or not plain(catalog.skill_fields) then return nil,"invalid_catalog" end
    local result={ids={},skills={},pairs={},variants={}}
    for id,row in pairs(catalog.by_id) do
        result.ids[id]=true
        if not plain(row) then return nil,"invalid_catalog_entry" end
        if row.variant_field~=nil then
            if not name(row.variant_field,96) or result.variants[row.variant_field] then return nil,"invalid_catalog_variant" end
            result.variants[row.variant_field]=id
        end
    end
    for field,value in pairs(catalog.skill_fields) do
        if value~=true then return nil,"invalid_catalog_skill" end
        result.skills[field]=true
    end
    if catalog.skills~=nil then
        if not plain(catalog.skills) then return nil,"invalid_catalog_skills" end
        for _,row in ipairs(catalog.skills) do
            if not plain(row) or not plain(row.skill_pairs) or not plain(row.skill_pairs.left)
                or not plain(row.skill_pairs.right) then return nil,"invalid_catalog_pairs" end
            result.pairs[#result.pairs+1]=clone(row.skill_pairs.left)
            result.pairs[#result.pairs+1]=clone(row.skill_pairs.right)
        end
    end
    if not valid_policy(result) then return nil,"invalid_policy" end
    return result
end

function M.validate_selection(selection,policy)
    if not valid_policy(policy) then return nil,"invalid_policy" end
    if not only_keys(selection,{selectedIds=true,skillOverrides=true,variantOverrides=true,customSkills=true}) then return nil,"invalid_selection" end
    local ok,err=bool_map(selection.selectedIds,policy.ids,true); if not ok then return nil,err end
    ok,err=bool_map(selection.skillOverrides,policy.skills,false); if not ok then return nil,err end
    local variants=selection.variantOverrides
    if variants==nil then variants={} end
    ok,err=bool_map(variants,policy.variants or {},false); if not ok then return nil,err end
    for field in pairs(variants) do
        if selection.selectedIds[policy.variants[field]]~=true then return nil,"variant_species_not_selected" end
    end
    for _,pair in ipairs(policy.pairs or {}) do
        if selection.skillOverrides[pair[1]]==true and selection.skillOverrides[pair[2]]==true then return nil,"conflicting_skill_pair" end
    end
    local custom; custom,err=custom_skills(selection.customSkills,policy); if not custom then return nil,err end
    local result=clone(selection); result.variantOverrides=clone(variants); result.customSkills=custom
    return result
end

local function valid_record(record,policy)
    if not only_keys(record,RECORD_KEYS) then return nil,"invalid_record" end
    local ok,err=identity(record); if not ok then return nil,err end
    return M.validate_selection({selectedIds=record.selectedIds,skillOverrides=record.skillOverrides,variantOverrides=record.variantOverrides,customSkills=record.customSkills},policy)
end
local function normalized_record(record)
    local result=clone(record)
    if result.variantOverrides==nil then result.variantOverrides={} end
    if result.customSkills==nil then result.customSkills={} end
    return result
end
local function valid_state(state,policy)
    if not valid_policy(policy) then return nil,"invalid_policy" end
    if not only_keys(state,{schema=true,records=true}) or state.schema~=1 or not plain(state.records) then return nil,"invalid_state" end
    local count=0
    for key,record in pairs(state.records) do
        count=count+1; if count>MAX_RECORDS then return nil,"too_many_snapshots" end
        local ok,err=valid_record(record,policy); if not ok then return nil,err end
        if key~=key_of(record) then return nil,"invalid_record_key" end
    end
    return count
end

-- Returns a new state. The adapter must persist it successfully before replacing
-- its current state. Identical bytes cannot acquire a different roster silently.
function M.capture(state,record,policy)
    local count,err=valid_state(state,policy); if not count then return nil,err end
    local ok; ok,err=valid_record(record,policy); if not ok then return nil,err end
    local key=key_of(record)
    local previous=state.records[key]
    local normalized=normalized_record(record)
    if previous and not equal(normalized_record(previous),normalized) then return nil,"fingerprint_collision" end
    if not previous and count>=MAX_RECORDS then return nil,"too_many_snapshots" end
    local result=clone(state); result.records[key]=normalized
    return result
end

function M.lookup(state,query,policy)
    local count,err=valid_state(state,policy); if not count then return nil,err end
    if not only_keys(query,QUERY_KEYS) then return nil,"invalid_query" end
    local ok; ok,err=identity(query); if not ok then return nil,err end
    local found=state.records[key_of(query)]
    if not found then return nil,"unknown_fingerprint" end
    if found.campaign_slot~=query.campaign_slot or found.mission_key~=query.mission_key then return nil,"binding_mismatch" end
    return normalized_record(found)
end

local function sorted_keys(value)
    local keys={}; for key in pairs(value) do keys[#keys+1]=key end; table.sort(keys); return keys
end
function M.encode(state,policy)
    local count,err=valid_state(state,policy); if not count then return nil,err end
    local lines={HEADER}
    for _,key in ipairs(sorted_keys(state.records)) do
        local record=state.records[key]
        lines[#lines+1]=table.concat({"SNAPSHOT",record.kind,record.native_slot,record.fingerprint,record.campaign_slot,record.mission_key},"\t")
        for _,id in ipairs(sorted_keys(record.selectedIds)) do lines[#lines+1]="UNIT\t"..id end
        for _,field in ipairs(sorted_keys(record.skillOverrides)) do lines[#lines+1]="SKILL\t"..field.."\t"..(record.skillOverrides[field] and "1" or "0") end
        for _,field in ipairs(sorted_keys(record.variantOverrides or {})) do lines[#lines+1]="VARIANT\t"..field.."\t"..(record.variantOverrides[field] and "1" or "0") end
        for _,id in ipairs(sorted_keys(record.customSkills or {})) do
            for _,side in ipairs({"left","right"}) do
                lines[#lines+1]="CSKILL\t"..id.."\t"..side.."\t"..(record.customSkills[id][side] or "none")
            end
        end
        lines[#lines+1]="END"
    end
    local bytes=table.concat(lines,"\n").."\n"
    if #bytes>MAX_BYTES then return nil,"state_too_large" end
    return bytes
end

function M.decode(bytes,policy)
    if not valid_policy(policy) then return nil,"invalid_policy" end
    if type(bytes)~="string" or #bytes==0 or #bytes>MAX_BYTES then return nil,"invalid_state_size" end
    -- Canonical LF only: reject partial writes, extra empty lines, NUL/control
    -- bytes and unrecognised tokens instead of silently dropping input.
    if bytes:sub(-1)~="\n" or bytes:find("\r",1,true) or bytes:find("%z") then return nil,"invalid_state_framing" end
    local state=M.new(); local current; local count=0
    local index=0
    for line in bytes:gmatch("([^\n]*)\n") do
        index=index+1
        if #line>600 or line=="" then return nil,"invalid_line" end
        if index==1 then
            if line~=HEADER then return nil,"unknown_schema" end
        elseif line:sub(1,9)=="SNAPSHOT\t" then
            if current then return nil,"nested_snapshot" end
            local kind,slot,hash,campaign,map=line:match("^SNAPSHOT\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
            current={kind=kind,native_slot=slot,fingerprint=hash,campaign_slot=campaign,mission_key=map,selectedIds={},skillOverrides={},variantOverrides={},customSkills={}}
            local ok,err=identity(current); if not ok then return nil,err end
            if state.records[key_of(current)] then return nil,"duplicate_snapshot" end
        elseif line:sub(1,5)=="UNIT\t" then
            if not current then return nil,"selection_outside_snapshot" end
            local id=line:match("^UNIT\t([A-Za-z0-9_-]+)$")
            if not id or not policy.ids[id] then return nil,"unknown_selection_field" end
            if current.selectedIds[id]~=nil then return nil,"duplicate_unit" end
            current.selectedIds[id]=true
        elseif line:sub(1,6)=="SKILL\t" then
            if not current then return nil,"selection_outside_snapshot" end
            local field,value=line:match("^SKILL\t([A-Za-z0-9_-]+)\t([01])$")
            if not field or not policy.skills[field] then return nil,"unknown_selection_field" end
            if current.skillOverrides[field]~=nil then return nil,"duplicate_skill" end
            current.skillOverrides[field]=value=="1"
        elseif line:sub(1,8)=="VARIANT\t" then
            if not current then return nil,"selection_outside_snapshot" end
            local field,value=line:match("^VARIANT\t([A-Za-z0-9_-]+)\t([01])$")
            if not field or not policy.variants or not policy.variants[field] then return nil,"unknown_variant_field" end
            if current.variantOverrides[field]~=nil then return nil,"duplicate_variant" end
            current.variantOverrides[field]=value=="1"
        elseif line:sub(1,7)=="CSKILL\t" then
            if not current then return nil,"selection_outside_snapshot" end
            local id,side,choice=line:match("^CSKILL\t([A-Za-z0-9_-]+)\t([a-z]+)\t([a-z_]+)$")
            if not CUSTOM_OPTIONS[id] or not policy.ids[id] or (side~="left" and side~="right") then return nil,"invalid_custom_skill_pair" end
            local row=current.customSkills[id] or {}; current.customSkills[id]=row
            if row[side]~=nil then return nil,"duplicate_custom_skill" end
            row[side]=choice
        elseif line=="END" then
            if not current then return nil,"unexpected_end" end
            local ok,err=valid_record(current,policy); if not ok then return nil,err end
            count=count+1; if count>MAX_RECORDS then return nil,"too_many_snapshots" end
            state.records[key_of(current)]=current; current=nil
        else return nil,"unknown_line" end
    end
    if current then return nil,"truncated_snapshot" end
    return state
end

function M.save(state,adapter,policy)
    if not plain(adapter) or type(adapter.atomic_write)~="function" then return nil,"invalid_writer" end
    local bytes,err=M.encode(state,policy); if not bytes then return nil,err end
    local ok,result,reason=pcall(adapter.atomic_write,bytes)
    if not ok then return nil,"write_exception" end
    if result~=true then return nil,reason or "write_failed" end
    return true
end

return M
