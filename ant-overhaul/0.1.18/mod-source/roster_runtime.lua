-- Story-local roster adapter. Loading it does not register hooks or retain UObjects.
-- Call on the game thread after the caller positively identifies a story mission.
local catalog = require("roster_catalog")
local native = require("native")
local groups = require("groups")
local M = {}

local function safe(fn)
    local ok,value=pcall(fn); if ok then return value end
end
local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function plain(t) return type(t)=="table" and getmetatable(t)==nil end
local function id(o)
    local value=safe(function() return o:GetAddress() end)
    return value~=nil and tostring(value) or nil
end
local function string_value(v)
    return type(v)=="string" and v or safe(function() return v:ToString() end)
end
local function unbox(v)
    local inner=safe(function() return v:get() end)
    if inner~=nil then return inner end
    return v
end
local function ordered_keys(t)
    local a={}; for k in pairs(t) do a[#a+1]=k end; table.sort(a); return a
end
local function copy(t)
    if type(t)~="table" then return t end
    local out={}; for k,v in pairs(t) do out[k]=copy(v) end; return out
end
local skill_group_ids={LeafcutterMajor="Leafcutter",MatabeleMedic="Matabele"}
local skill_by_field,guard_fields,guard_seen={},{},{}
local variant_owners,point_fields_by_id={},{}
for _,row in ipairs(catalog.entries) do
    if row.variant_field then variant_owners[row.variant_field]=row.id end
    local group=groups.by_id[skill_group_ids[row.id] or row.id]
    if group then point_fields_by_id[row.id]=copy(group.fields) end
end
local function guard(field)
    if not guard_seen[field] then guard_seen[field]=true; guard_fields[#guard_fields+1]=field end
end
for _,row in ipairs(catalog.skills) do
    for _,field in ipairs(row.fields) do skill_by_field[field]=row end
end
for _,field in ipairs(catalog.protected_colony_fields) do guard(field) end
for _,row in ipairs(groups.list) do for _,field in ipairs(row.fields) do guard(field) end end
for _,row in ipairs(catalog.entries) do if row.upgrade_field then guard(row.upgrade_field) end end
for _,field in ipairs({"WorkerMaxUpgradeLevel","ExplodingAntSoldierMaxUpgradeLevel",
    "ExplodingTermiteWorkerMaxUpgradeLevel","NarrowHeadedRangedMaxUpgradeLevel",
    "HeatResistanceUpgradeLevel","LaserReflectivityUpgradeLevel",
    "ElectricalGroundingUpgradeLevel","ChemicalResistanceUpgradeLevel"}) do guard(field) end

local defaults={
    valid=native.valid_object, object_id=id, world_id=native.world_id,
    local_controller=native.get_local_controller, owned=native.is_owned,
    read=function(ctx,field) return ctx.grid.ColonySetup[field] end,
    write=function(ctx,field,value) ctx.grid.ColonySetup[field]=value end,
    cap_get=function(ctx,colony) return unbox(ctx.gs:GetPopCapByID(colony)) end,
    cap_set=function(ctx,colony,value) ctx.gs:SetPopCapByID(colony,value) end,
    at_cap=function(ctx,colony) return unbox(ctx.gs:IsPlayerAtPopCap(colony)) end,
    grid_for=function(ctx,colony) return unbox(ctx.gs:GetTileGridByColonyID(colony)) end,
    colony_id=function(ctx) return tonumber(unbox(ctx.pc:GetColonyID())) end,
    creatures=function() return FindAllOf("Creature") or {} end,
    creature_group=function(c)
        local name=string_value(c.CreatureName)
        return name and groups.by_creature[name] and groups.by_creature[name].id
    end,
    creature_ready=function(c,ctx,group)
        if group=="Queen" then
            return native.valid_object(ctx.grid.ColonyQueen) and id(c)==id(ctx.grid.ColonyQueen)
        end
        local cls=StaticFindObject("/Script/EotU.ColonyCreature")
        return native.valid_object(cls) and c:IsA(cls)==true
            and native.valid_object(c.NurseryTile) and native.world_id(c.NurseryTile)==native.world_id(ctx.gs)
    end,
    refresh_creature=function(c) c:ChangeCreatureLevel(true) end,
    hud=function(ctx)
        if ctx.hud then return ctx.hud end
        local hud=ctx.pc:GetHUD()
        if native.valid_object(hud) then return hud.TugOfWarWidgetInstance end
    end,
    refresh_hud=function(hud) hud:SetupBuildMenuButtons() end,
}

function M.new(overrides)
    local d={}; for k,v in pairs(defaults) do d[k]=v end
    for k,v in pairs(overrides or {}) do d[k]=v end
    local api,active,active_points,busy={},nil,nil,false
    local function context(ctx)
        if type(ctx)~="table" or ctx.story~=true then return nil,"story_context_required" end
        for _,key in ipairs({"gs","gm","pc","grid"}) do
            if not d.valid(ctx[key]) then return nil,"invalid_"..key end
        end
        local world=d.world_id(ctx.gs)
        local expected=(type(ctx.world)=="number" or type(ctx.world)=="string") and tostring(ctx.world) or d.object_id(ctx.world)
        if world==nil or tostring(world)~=expected then return nil,"world_changed" end
        for _,key in ipairs({"gm","pc","grid"}) do
            if tostring(d.world_id(ctx[key]))~=tostring(world) then return nil,"different_world_"..key end
        end
        local pc=d.local_controller(ctx.gs)
        if not d.valid(pc) or d.object_id(pc)~=d.object_id(ctx.pc) then return nil,"local_controller_changed" end
        local colony=d.colony_id(ctx)
        if not finite(colony) or colony%1~=0 or colony<0 or colony>2147483647 then return nil,"invalid_colony_id" end
        if tonumber(ctx.grid.ColonyID)~=colony or not d.owned(ctx.grid,ctx.gs) then return nil,"grid_not_owned" end
        local current=d.grid_for(ctx,colony)
        if not d.valid(current) or d.object_id(current)~=d.object_id(ctx.grid) then return nil,"grid_replaced" end
        local identity={world=tostring(world),colony=colony}
        for _,key in ipairs({"gs","gm","pc","grid"}) do
            identity[key]=d.object_id(ctx[key]); if not identity[key] then return nil,"identity_missing_"..key end
        end
        identity.key=identity.world..":"..identity.gs..":"..identity.gm..":"..identity.pc..":"..identity.grid..":"..colony
        return identity
    end
    local function same_context(ctx,identity)
        local ok,live,why=pcall(context,ctx)
        if not ok then return nil,tostring(live) end
        if not live then return nil,why end
        if live.key~=identity.key then return nil,"receipt_context_changed" end
        return live
    end
    local function selection_plan(ctx,selection)
        if not plain(selection) then return nil,"invalid_selection" end
        for key in pairs(selection) do
            if key~="selectedIds" and key~="skillOverrides" and key~="variantOverrides" then return nil,"unexpected_selection_field:"..tostring(key) end
        end
        if not plain(selection.selectedIds) or not plain(selection.skillOverrides or {})
            or not plain(selection.variantOverrides or {}) then return nil,"invalid_selection_tables" end
        local selected,desired,signature,seen={},{},{},{}
        local format
        for key,value in pairs(selection.selectedIds) do
            local unit
            if type(key)=="string" and value==true then
                if format=="array" then return nil,"mixed_selected_ids" end
                format="set"; unit=key
            elseif type(key)=="number" and key%1==0 and key>=1 and key<=#selection.selectedIds then
                if format=="set" then return nil,"mixed_selected_ids" end
                format="array"; unit=value
            else return nil,"invalid_selected_ids" end
            if type(unit)~="string" or not catalog.by_id[unit] or seen[unit] then return nil,"unknown_or_duplicate_id:"..tostring(unit) end
            seen[unit]=true
            -- Old save records remain readable. A retired supplemental choice
            -- grants no permission, and never clears a native mission's flag.
            if catalog.is_selectable(unit,ctx.dlc_available) then
                selected[unit]=true; desired[catalog.by_id[unit].flag]=true
            end
        end
        local variants={}
        for field,value in pairs(selection.variantOverrides or {}) do
            local owner=variant_owners[field]
            if not owner or not selected[owner] or type(value)~="boolean" then return nil,"invalid_variant_override:"..tostring(field) end
            desired[field]=value; variants[field]=value
        end
        local overrides=selection.skillOverrides or {}
        for field,value in pairs(overrides) do
            if not catalog.skill_fields[field] or type(value)~="boolean" then return nil,"invalid_skill_override:"..tostring(field) end
            local owner=skill_by_field[field]
            local entry=owner and catalog.by_id[owner.id]
            if not entry or not entry.dlc or catalog.is_selectable(entry.id,ctx.dlc_available) then
                desired[field]=value
            end
        end
        for _,row in ipairs(catalog.skills) do
            for _,pair in pairs(row.skill_pairs) do
                if overrides[pair[1]]~=nil or overrides[pair[2]]~=nil then
                    local a=overrides[pair[1]]; if a==nil then a=d.read(ctx,pair[1]) end
                    local b=overrides[pair[2]]; if b==nil then b=d.read(ctx,pair[2]) end
                    if type(a)~="boolean" or type(b)~="boolean" then return nil,"unreadable_skill_pair" end
                    if a and b then return nil,"mutually_exclusive_skills:"..row.id end
                end
            end
        end
        for _,field in ipairs(ordered_keys(desired)) do signature[#signature+1]=field.."="..tostring(desired[field]) end
        return {desired=desired,variants=variants,selected=selected,signature=table.concat(signature,";")}
    end
    local function guards(ctx)
        local out={}
        for _,field in ipairs(guard_fields) do
            local value=d.read(ctx,field)
            if type(value)~="boolean" and not finite(value) then error("guard_unreadable:"..field) end
            out[field]=value
        end
        if ctx.capture_profile then
            local value=ctx.capture_profile(ctx)
            if type(value)~="string" and type(value)~="boolean" and not finite(value) then error("invalid_profile_signature") end
            out.__profile=value
        end
        return out
    end
    local function check_guards(ctx,before,expected_changes)
        local now=guards(ctx)
        for field,value in pairs(before) do
            if expected_changes and expected_changes[field]~=nil then value=expected_changes[field] end
            if now[field]~=value then error("protected_value_changed:"..field) end
        end
    end
    local function targets(ctx,changed)
        local wanted,out,seen={},{},{}
        for field in pairs(changed) do
            local row=skill_by_field[field]
            if row then wanted[skill_group_ids[row.id] or row.id]=true end
        end
        if next(wanted)==nil then return out end
        local list=d.creatures(ctx)
        if type(list)~="table" then error("creature_list_unavailable") end
        for _,c in ipairs(list) do
            local group=d.valid(c) and d.owned(c,ctx.gs) and d.creature_group(c)
            if group and wanted[group] then
                local key=d.object_id(c)
                if not key then error("creature_identity_missing") end
                local hp,full=tonumber(c.Health),tonumber(c.FullHealth)
                if not finite(hp) or not finite(full) or full<=0 then error("creature_health_unreadable") end
                if hp>0 and not seen[key] then
                    if not d.creature_ready(c,ctx,group) then error("skill_creature_not_ready:"..group) end
                    seen[key]=true; out[#out+1]={object=c,id=key,hp=hp}
                end
            end
        end
        return out
    end
    local function preserve_health(ctx,list)
        for _,entry in ipairs(list) do
            local c=entry.object
            if d.valid(c) and d.object_id(c)==entry.id and d.owned(c,ctx.gs) then
                local full=tonumber(c.FullHealth)
                if not finite(full) or full<=0 then error("refreshed_full_health_invalid") end
                c.Health=math.max(0,math.min(entry.hp,full))
            end
        end
    end
    local function refresh(ctx,identity,list)
        for _,entry in ipairs(list) do
            local _,why=same_context(ctx,identity); if why then error(why) end
            if not d.valid(entry.object) or not d.owned(entry.object,ctx.gs) or d.object_id(entry.object)~=entry.id then
                error("skill_creature_context_changed")
            end
            d.refresh_creature(entry.object,ctx)
        end
        if #list>0 and ctx.after_skill_refresh then
            local actors={}; for _,entry in ipairs(list) do actors[#actors+1]=entry.object end
            if ctx.after_skill_refresh(actors,ctx)==false then error("extra_stat_reapply_failed") end
        end
        local _,why=same_context(ctx,identity); if why then error(why) end
        preserve_health(ctx,list)
    end
    local function menu(ctx,receipt)
        if not receipt.menu_pending then return false end
        if ctx.defer_hud_refresh then receipt.menu_pending=false; return false end
        local hud=d.hud(ctx)
        if not d.valid(hud) then return false end
        if tostring(d.world_id(hud))~=receipt.identity.world then error("hud_world_mismatch") end
        d.refresh_hud(hud,ctx); receipt.menu_pending=false
        receipt.menu_refreshes=receipt.menu_refreshes+1
        return true
    end
    function api.validate(ctx,selection)
        local ok,identity,why=pcall(context,ctx)
        if not ok then return nil,tostring(identity) end
        if not identity then return nil,why end
        local success,plan,err=pcall(selection_plan,ctx,selection)
        if not success then return nil,tostring(plan) end
        if not plan then return nil,err end
        return {identity=identity,signature=plan.signature,desired=plan.desired,variants=plan.variants,selected=plan.selected}
    end
    -- Copies exact saved counts into this mission's grid. This is inheritance,
    -- not a purchase: no arithmetic, profile writes, buff creation, or actor spawn.
    -- source_ng is the caller's verified source profile NewGamePlusLevel.
    function api.inherit_points(ctx,selection,profile_values,source_ng)
        if busy then return nil,"inherit_points_reentrant" end
        local plan,why=api.validate(ctx,selection); if not plan then return nil,why end
        if not finite(source_ng) or source_ng%1~=0 then return nil,"source_ng_required" end
        if source_ng<=0 then return {skipped=true,reason="no_new_game_plus",identity=plan.identity,changes={},changed=false} end
        if not plain(profile_values) then return nil,"profile_values_must_be_plain_table" end
        local desired,signature={},{}
        for selected in pairs(plan.selected) do
            for _,field in ipairs(point_fields_by_id[selected] or {}) do
                local value=profile_values[field]
                if not finite(value) or value%1~=0 or value<0 or value>2147483647 then return nil,"invalid_profile_point:"..field end
                desired[field]=value
            end
        end
        for _,field in ipairs(ordered_keys(desired)) do signature[#signature+1]=field.."="..tostring(desired[field]) end
        signature=table.concat(signature,";")
        if active_points and active_points.identity.key~=plan.identity.key then active_points.status="expired"; active_points=nil end
        if active_points and active_points.signature~=signature then return nil,"point_inheritance_changed_same_grid_restore_first" end
        busy=true
        local delta,before={}
        local receipt=active_points and copy(active_points) or {identity=plan.identity,signature=signature,changes={},status="active",applies=0}
        local ok,err=pcall(function()
            before=guards(ctx)
            for field,value in pairs(desired) do
                local current=d.read(ctx,field)
                if not finite(current) or current%1~=0 or current<0 or current>2147483647 then error("invalid_grid_point:"..field) end
                if current~=value then delta[field]={before=current,after=value} end
            end
            local _,invalid=same_context(ctx,plan.identity); if invalid then error(invalid) end
            for _,field in ipairs(ordered_keys(delta)) do
                d.write(ctx,field,delta[field].after); delta[field].written=true
            end
            check_guards(ctx,before,desired)
            for field,item in pairs(delta) do
                if not receipt.changes[field] then receipt.changes[field]={before=item.before,after=item.after}
                else receipt.changes[field].after=item.after end
            end
            receipt.applies=receipt.applies+1; receipt.changed=next(delta)~=nil
            receipt.source_ng=source_ng; receipt.source_unchanged=true
        end)
        if not ok then
            local rolled_back=false
            if same_context(ctx,plan.identity) then
                rolled_back=pcall(function()
                    for field,item in pairs(delta) do
                        if item.written and d.read(ctx,field)==item.after then d.write(ctx,field,item.before) end
                    end
                    if before then check_guards(ctx,before) end
                end)
            end
            busy=false
            return nil,tostring(err).."; rollback="..tostring(rolled_back)
        end
        busy=false; active_points=receipt
        return receipt
    end
    function api.restore_points(ctx,receipt)
        if busy then return nil,"restore_points_reentrant" end
        if type(receipt)~="table" or type(receipt.identity)~="table" then return nil,"invalid_points_receipt" end
        local live,why=same_context(ctx,receipt.identity)
        if not live then receipt.status="expired"; if receipt==active_points then active_points=nil end; return nil,why end
        if receipt.skipped then return {restored=0,conflicts={}} end
        if receipt~=active_points or receipt.status=="expired" then return nil,"points_receipt_not_active" end
        busy=true
        local result={restored=0,conflicts={}}
        local delta,before={}
        local ok,err=pcall(function()
            before=guards(ctx)
            local expected={}
            for field,item in pairs(receipt.changes) do
                if d.read(ctx,field)==item.after then
                    delta[field]={before=item.after,after=item.before}; expected[field]=item.before
                else result.conflicts[#result.conflicts+1]=field end
            end
            for _,field in ipairs(ordered_keys(delta)) do
                d.write(ctx,field,delta[field].after); delta[field].written=true
                result.restored=result.restored+1
            end
            check_guards(ctx,before,expected)
        end)
        if not ok then
            local rolled_back=false
            if same_context(ctx,receipt.identity) then
                rolled_back=pcall(function()
                    for field,item in pairs(delta) do
                        if item.written and d.read(ctx,field)==item.after then d.write(ctx,field,item.before) end
                    end
                    if before then check_guards(ctx,before) end
                end)
            end
            busy=false; return nil,tostring(err).."; rollback="..tostring(rolled_back)
        end
        busy=false; active_points=nil; receipt.status="restored"
        return result
    end
    function api.apply(ctx,selection)
        if busy then return nil,"apply_reentrant" end
        local plan,why=api.validate(ctx,selection); if not plan then return nil,why end
        if active and active.identity.key~=plan.identity.key then active.status="expired"; active=nil end
        if active and active.signature~=plan.signature then return nil,"selection_changed_same_grid_restore_first" end
        busy=true
        local delta,initial,actors,oldcap={},nil,{},nil
        local refresh_started=false
        local receipt=active and copy(active) or {identity=plan.identity,signature=plan.signature,changes={},skill_pairs={},
            status="active",menu_pending=false,menu_refreshes=0,skill_refreshes=0,applies=0}
        local ok,err=pcall(function()
            initial=guards(ctx)
            oldcap=tonumber(d.cap_get(ctx,plan.identity.colony))
            if not finite(oldcap) or oldcap%1~=0 then error("population_cap_unreadable") end
            for _,field in ipairs(ordered_keys(plan.desired)) do
                local value=d.read(ctx,field)
                if type(value)~="boolean" then error("colony_flag_unreadable:"..field) end
                if value~=plan.desired[field] then delta[field]={before=value,after=plan.desired[field]} end
            end
            actors=targets(ctx,delta)
            local _,invalid=same_context(ctx,plan.identity); if invalid then error(invalid) end
            -- Clear the old option before enabling its mutually exclusive partner.
            for _,desired in ipairs({false,true}) do
                for _,field in ipairs(ordered_keys(delta)) do
                    if delta[field].after==desired then d.write(ctx,field,desired); delta[field].written=true end
                end
            end
            for field,item in pairs(delta) do if d.read(ctx,field)~=item.after then error("flag_readback_failed:"..field) end end
            if oldcap~=catalog.unlimited_population then d.cap_set(ctx,plan.identity.colony,catalog.unlimited_population) end
            if tonumber(d.cap_get(ctx,plan.identity.colony))~=0 or d.at_cap(ctx,plan.identity.colony)~=false then error("unlimited_population_readback_failed") end
            refresh_started=#actors>0
            refresh(ctx,plan.identity,actors)
            check_guards(ctx,initial,plan.variants)
            for field,item in pairs(delta) do
                if not receipt.changes[field] then receipt.changes[field]={before=item.before,after=item.after}
                else receipt.changes[field].after=item.after end
                if not catalog.skill_fields[field] then receipt.menu_pending=true end
            end
            for _,row in ipairs(catalog.skills) do
                for side,pair in pairs(row.skill_pairs) do
                    if delta[pair[1]] or delta[pair[2]] then
                        local key=row.id..":"..side
                        local pair_record=receipt.skill_pairs[key] or {fields={pair[1],pair[2]},expected={}}
                        for _,field in ipairs(pair) do pair_record.expected[field]=d.read(ctx,field) end
                        receipt.skill_pairs[key]=pair_record
                    end
                end
            end
            if receipt.cap_before==nil and oldcap~=0 then receipt.cap_before=oldcap end
            receipt.skill_refreshes=receipt.skill_refreshes+#actors
            receipt.applies=receipt.applies+1
            receipt.changed=next(delta)~=nil or oldcap~=0
            receipt.numeric_unchanged=true
            menu(ctx,receipt)
        end)
        if not ok then
            local restored=false
            if same_context(ctx,plan.identity) then
                restored=pcall(function()
                    for _,desired in ipairs({false,true}) do
                        for field,item in pairs(delta) do
                            if item.written and item.before==desired and d.read(ctx,field)==item.after then d.write(ctx,field,item.before) end
                        end
                    end
                    if oldcap~=nil and tonumber(d.cap_get(ctx,plan.identity.colony))==0 then d.cap_set(ctx,plan.identity.colony,oldcap) end
                    if refresh_started then refresh(ctx,plan.identity,actors) end
                    if initial then check_guards(ctx,initial) end
                end)
                pcall(preserve_health,ctx,actors)
            end
            busy=false
            return nil,tostring(err).."; rollback="..tostring(restored)
        end
        busy=false; active=receipt
        return receipt
    end
    function api.restore(ctx,receipt)
        if busy then return nil,"restore_reentrant" end
        if receipt~=active or receipt.status=="expired" then return nil,"receipt_not_active" end
        local live,why=same_context(ctx,receipt.identity)
        if not live then receipt.status="expired"; active=nil; return nil,why end
        busy=true
        local result={restored=0,conflicts={},menu_refreshed=false}
        local actors={}
        local ok,err=pcall(function()
            local before=guards(ctx)
            local restore_fields,blocked,expected_variants={},{},{}
            for _,pair in pairs(receipt.skill_pairs) do
                local conflict=false
                for _,field in ipairs(pair.fields) do if d.read(ctx,field)~=pair.expected[field] then conflict=true end end
                if conflict then for _,field in ipairs(pair.fields) do blocked[field]=true end end
            end
            for field,item in pairs(receipt.changes) do
                if not blocked[field] and d.read(ctx,field)==item.after then
                    restore_fields[field]={before=item.after,after=item.before}
                    if variant_owners[field] then expected_variants[field]=item.before end
                else result.conflicts[#result.conflicts+1]=field end
            end
            actors=targets(ctx,restore_fields)
            for _,desired in ipairs({false,true}) do
                for field,item in pairs(restore_fields) do if item.after==desired then d.write(ctx,field,desired) end end
            end
            for field,item in pairs(restore_fields) do
                if d.read(ctx,field)~=item.after then error("restore_readback_failed:"..field) end
                result.restored=result.restored+1
                if not catalog.skill_fields[field] then receipt.menu_pending=true end
            end
            if receipt.cap_before~=nil then
                if tonumber(d.cap_get(ctx,live.colony))==0 then
                    d.cap_set(ctx,live.colony,receipt.cap_before)
                    if tonumber(d.cap_get(ctx,live.colony))~=receipt.cap_before then error("restore_cap_readback_failed") end
                else result.conflicts[#result.conflicts+1]="PopCap" end
            end
            refresh(ctx,live,actors)
            check_guards(ctx,before,expected_variants)
            result.menu_refreshed=menu(ctx,receipt)
        end)
        if same_context(ctx,receipt.identity) then pcall(preserve_health,ctx,actors) end
        busy=false
        if not ok then return nil,tostring(err) end
        receipt.status="restored"; active=nil
        return result
    end
    function api.finalize(ctx,receipt)
        if busy then return nil,"finalize_reentrant" end
        if receipt~=active then return nil,"receipt_not_active" end
        local live,why=same_context(ctx,receipt.identity)
        if not live then receipt.status="expired"; active=nil; return nil,why end
        local ok,err=pcall(menu,ctx,receipt)
        if not ok then return nil,tostring(err) end
        receipt.status="finalized"
        return {numeric_unchanged=receipt.numeric_unchanged,menu_pending=receipt.menu_pending,
            menu_refreshes=receipt.menu_refreshes,skill_refreshes=receipt.skill_refreshes}
    end
    return api
end

local instance=M.new()
M.validate,M.apply,M.restore,M.finalize=instance.validate,instance.apply,instance.restore,instance.finalize
M.inherit_points,M.restore_points=instance.inherit_points,instance.restore_points
M.guard_fields=guard_fields
M.point_fields_by_id=point_fields_by_id
M.variant_owners=variant_owners
return M
