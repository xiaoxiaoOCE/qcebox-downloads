-- Temporary Gate-challenge save boundary. No hooks are installed at load time.
-- before_save/after_save belong in native save hooks; tick runs on the game
-- thread. Blueprint victory/defeat hooks only enqueue, never refresh actors.
local catalog = require("roster_catalog")
local M = {}
local allowed = {}
for _,row in ipairs(catalog.entries) do
    allowed[row.flag]=true
    if row.variant_field then allowed[row.variant_field]=true end
end
for field in pairs(catalog.skill_fields) do allowed[field]=true end

local function plain(t) return type(t)=="table" and getmetatable(t)==nil end
local function unbox(value)
    local ok,result=pcall(function() return value:get() end)
    if ok and result~=nil then return result end
    return value
end
local function keys(t)
    local list={}; for field in pairs(t) do list[#list+1]=field end
    table.sort(list); return list
end

-- GateEndPlay is deliberately absent: it grants rewards before its Blueprint
-- posthook. The four maps' VictoryAction/DefeatAction do not save ColonySetup.
-- All eight are full FunctionExport bodies, not event wrappers calling
-- ExecuteUbergraph. There are no verified event-entry offsets to duplicate.
local end_hooks,end_hooks_by_map={},{}
for _,map in ipairs({"LabFormicarium","LabFormicariumStage2","LabFormicariumStage3","LabFormicariumStage4"}) do
    local current={};end_hooks_by_map[map]=current
    for _,event in ipairs({"VictoryAction","DefeatAction"}) do
        local entry={event=event,path="/Game/Levels/Formicarium/Lab/"..map.."."..map.."_C:"..event}
        end_hooks[#end_hooks+1]=entry;current[#current+1]=entry
    end
end
M.end_hooks=end_hooks

function M.install(api)
    assert(type(api)=="table" and type(api.get_active)=="function"
        and type(api.get_context)=="function" and type(api.finish)=="function"
        and type(api.valid)=="function", "invalid_challenge_adapter")
    local control={last_error=nil}
    local hooks,reported={},{}
    local pending,finishing,stopped=nil,false,false
    local completed=setmetatable({}, {__mode="k"})
    local read=api.read_colony or function(ctx,field) return ctx.grid.ColonySetup[field] end
    local write=api.write_colony or function(ctx,field,value) ctx.grid.ColonySetup[field]=value end
    local function report(err)
        control.last_error=tostring(err)
        if not reported[control.last_error] then
            reported[control.last_error]=true
            if api.log then pcall(api.log,"[StoryRosterChallenge] "..control.last_error) end
        end
    end
    local function address(object)
        if not api.valid(object) then return nil end
        local value=object:GetAddress()
        return value~=nil and tostring(value) or nil
    end
    local function world_id(value)
        if type(value)=="string" or type(value)=="number" then return tostring(value) end
        return address(value)
    end
    local function identity(ctx)
        if type(ctx)~="table" then error("challenge_context_unavailable") end
        local result={world=world_id(ctx.world),slot=ctx.slot}
        if not result.world or type(result.slot)~="string" or result.slot=="" then error("challenge_identity_unavailable") end
        for _,field in ipairs({"gm","gs","pc","grid"}) do
            result[field]=address(ctx[field]); if not result[field] then error("invalid_challenge_"..field) end
            if world_id(ctx[field]:GetWorld())~=result.world then error("challenge_world_mismatch:"..field) end
        end
        return result
    end
    local function equal_identity(left,right)
        for _,field in ipairs({"world","slot","gm","gs","pc","grid"}) do
            if left[field]~=right[field] then return false end
        end
        return true
    end
    local function matching(ctx,wanted)
        local ok,current=pcall(identity,ctx)
        return ok and equal_identity(current,wanted)
    end
    local function current_challenge()
        local active=api.get_active()
        if type(active)~="table" or active.challenge~=true or completed[active] then return nil end
        local ctx=api.get_context()
        local current=identity(ctx)
        if not matching(active.ctx,current) then error("active_challenge_context_changed") end
        return active,ctx,current
    end
    local function still_current(mask)
        local ok,result=pcall(function()
            return api.get_active()==mask.active and mask.active.challenge==true and not completed[mask.active]
                and matching(api.get_context(),mask.identity)
                and matching(mask.ctx,mask.identity)
        end)
        return ok and result
    end
    local function write_order(ctx,changes,target,only_if)
        -- A skill pair must never transiently contain both options.
        for _,value in ipairs({false,true}) do
            for _,field in ipairs(keys(changes)) do
                local item=changes[field]
                if item[target]==value and (not only_if or read(ctx,field)==item[only_if]) then
                    item.attempted=true
                    write(ctx,field,value)
                    if read(ctx,field)~=value then error("challenge_flag_readback_failed:"..field) end
                end
            end
        end
    end
    function control.before_save(receiver,skip_overlay_param)
        if stopped then return nil end
        local mask
        local ok,result=pcall(function()
            local active,ctx,current=current_challenge()
            if not active then return nil end
            if address(unbox(receiver))~=current.gm then return nil end
            if not plain(active.receipt) or not plain(active.receipt.changes) then error("invalid_challenge_receipt") end
            mask={active=active,ctx=ctx,identity=current,changes={},status="preparing"}
            for field,item in pairs(active.receipt.changes) do
                if not allowed[field] or not plain(item) or type(item.before)~="boolean"
                    or type(item.after)~="boolean" then error("invalid_challenge_change:"..tostring(field)) end
                local current_value=read(ctx,field)
                if type(current_value)~="boolean" then error("challenge_flag_unreadable:"..field) end
                -- A nested save sees the already-masked 'before' value and owns
                -- no restoration for it. Other save observers may also restore it.
                if item.before~=item.after and current_value==item.after then
                    mask.changes[field]={before=item.before,after=item.after}
                end
            end
            if skip_overlay_param~=nil then
                local previous=unbox(skip_overlay_param)
                if type(previous)~="boolean" then error("skip_overlay_parameter_unreadable") end
                mask.skip_parameter=skip_overlay_param; mask.skip_before=previous
                if not previous then
                    mask.skip_attempted=true
                    skip_overlay_param:set(true)
                    if unbox(skip_overlay_param)~=true then error("synchronous_save_parameter_failed") end
                end
            end
            if not still_current(mask) then error("challenge_changed_before_save") end
            write_order(ctx,mask.changes,"before")
            mask.status="masked"
            return mask
        end)
        if ok then return result end
        local rollback=true
        if mask then
            if still_current(mask) then
                local written={}
                for field,item in pairs(mask.changes) do if item.attempted then written[field]=item end end
                rollback=pcall(write_order,mask.ctx,written,"after","before")
            else rollback=false end
            if mask.skip_attempted then
                local restored=pcall(function()
                    mask.skip_parameter:set(mask.skip_before)
                    if unbox(mask.skip_parameter)~=mask.skip_before then error("skip_parameter_rollback_failed") end
                end)
                rollback=rollback and restored
            end
            mask.status="failed"
        end
        local err=tostring(result).."; rollback="..tostring(rollback)
        report(err)
        -- This is an error, not a successful noop. The caller owns the native
        -- hook and must not silently continue a save with temporary flags.
        return nil,err
    end
    function control.after_save(mask)
        if mask==nil then return {restored=0,conflicts={},noop=true} end
        if type(mask)~="table" or mask.status~="masked" then return nil,"save_mask_not_active" end
        if not still_current(mask) then mask.status="expired"; return nil,"save_mask_context_changed" end
        local result={restored=0,conflicts={}}
        local ok,err=pcall(function()
            for _,value in ipairs({false,true}) do
                for _,field in ipairs(keys(mask.changes)) do
                    local item=mask.changes[field]
                    if item.after==value then
                        if read(mask.ctx,field)==item.before then
                            write(mask.ctx,field,item.after)
                            if read(mask.ctx,field)~=item.after then error("challenge_restore_readback_failed:"..field) end
                            result.restored=result.restored+1
                        else result.conflicts[#result.conflicts+1]=field end
                    end
                end
            end
        end)
        if not ok then report(err); return nil,tostring(err) end
        mask.status="restored"
        return result
    end
    local function enqueue(receiver,event)
        if stopped then return end
        local ok,err=pcall(function()
            local active,ctx,current=current_challenge()
            if not active then return end
            local actor=unbox(receiver)
            if not api.valid(actor) or world_id(actor:GetWorld())~=current.world then return end
            if pending and pending.active==active then return end
            pending={active=active,ctx=ctx,identity=current,event=event,attempts=0}
        end)
        if not ok then report(err) end
    end
    -- Called explicitly before enabling a challenge's temporary configuration.
    -- Only this world's two functions can be relevant. Searching unloaded Lab
    -- maps is expensive, and gameplay ticks must never perform that discovery.
    function control.ensure_hooks(ctx)
        local result=control.status();result.ready=false
        if stopped then return result end
        local ok,map=pcall(function()
            local current=ctx or api.get_context()
            if type(current)~="table" or not api.valid(current.world) then return nil end
            return current.world:GetFName():ToString()
        end)
        local entries=ok and end_hooks_by_map[map]
        if not entries then result.reason="challenge_world_not_supported";return result end
        local find=api.find_object or StaticFindObject
        local register=api.register_hook or RegisterHook
        if type(find)=="function" and type(register)=="function" then
            for _,entry in ipairs(entries) do
                if not hooks[entry.path] then
                    local ok,object=pcall(find,entry.path)
                    if ok and api.valid(object) then
                        local event=entry.event
                        -- Non-/Script Blueprint targets execute the first
                        -- RegisterHook callback after the function returns.
                        local success,a,b=pcall(register,entry.path,
                            function(receiver) enqueue(receiver,event) end)
                        if success and type(a)=="number" and type(b)=="number" then hooks[entry.path]={a,b}
                        else report("challenge_end_hook_failed:"..entry.path..":"..tostring(success and "invalid_hook_handles" or a)) end
                    end
                end
            end
        end
        result=control.status();result.map=map
        result.ready=hooks[entries[1].path]~=nil and hooks[entries[2].path]~=nil
        if not result.ready then result.reason="challenge_end_hooks_unavailable" end
        return result
    end
    function control.tick()
        if stopped then return control.status() end
        -- Finish requests are not rate limited and do no hook discovery.
        if pending and not finishing then
            local item=pending
            if not still_current(item) then pending=nil
            else
                finishing=true; item.attempts=item.attempts+1
                local ok,result,err=pcall(api.finish,item.ctx)
                finishing=false
                if ok and result==true then
                    completed[item.active]=true
                    if pending==item then pending=nil end
                else report("challenge_finish_failed:"..tostring(ok and (err or result) or result)) end
            end
        end
        return control.status()
    end
    function control.status()
        local count=0; for _ in pairs(hooks) do count=count+1 end
        return {registered=count,pending=pending~=nil,event=pending and pending.event,
            attempts=pending and pending.attempts or 0,last_error=control.last_error,stopped=stopped}
    end
    function control.stop()
        -- Mute first so an already-dispatched Blueprint callback cannot queue
        -- work after F8 or an isolated-runtime module reload.
        stopped=true; pending=nil
        local unregister=api.unregister_hook or UnregisterHook
        local removed,failures=0,{}
        for path,handles in pairs(hooks) do
            local ok,result=pcall(function()
                if type(unregister)~="function" then error("unregister_hook_unavailable") end
                return unregister(path,handles[1],handles[2])
            end)
            if ok and result~=false then hooks[path]=nil; removed=removed+1
            else failures[#failures+1]=path..":"..tostring(result) end
        end
        if #failures>0 then
            local err="challenge_stop_failed:"..table.concat(failures,";")
            report(err); return nil,err
        end
        return {unregistered=removed,stopped=true}
    end
    return control
end
return M
