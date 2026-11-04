local source = debug.getinfo(1,"S").source:sub(2)
local dir = assert(source:match("^(.*)[/\\]"))
local fileio = dofile(dir.."/unicode_fs.lua")
local core = dofile(dir.."/core.lua")
local native = dofile(dir.."/native.lua")
local extra = dofile(dir.."/extra.lua")
local groups = dofile(dir.."/groups.lua")
local sha256 = dofile(dir.."/sha256.lua")
-- A synchronous skill transaction can inspect the same bytes through several
-- modules. Reuse only exact content within that transaction; readers still
-- reopen and validate the live native files at every payment/save boundary.
local raw_sha256,hash_scope=sha256,nil
sha256=function(bytes)
 local scope=hash_scope
 if not scope then return raw_sha256(bytes)end
 local known=scope.cache[bytes]
 if known then scope.reuses=scope.reuses+1;return known end
 local started=os.clock();local result=raw_sha256(bytes)
 scope.calls=scope.calls+1;scope.bytes=scope.bytes+#bytes
 scope.cpu_ms=scope.cpu_ms+(os.clock()-started)*1000
 if scope.retained+#bytes<=64*1024*1024 then
  scope.cache[bytes]=result;scope.retained=scope.retained+#bytes
 end
 return result
end
local function begin_hash_scope()
 assert(not hash_scope,'hash_scope_already_active')
 hash_scope={cache={},retained=0,calls=0,bytes=0,reuses=0,cpu_ms=0}
 return hash_scope
end
local function end_hash_scope(token)
 assert(hash_scope==token and token~=nil,'hash_scope_token_mismatch')
 hash_scope=nil
 return{calls=token.calls,bytes=token.bytes,reuses=token.reuses,cpu_ms=token.cpu_ms}
end
local ui = dofile(dir.."/ui.lua")
local roster = dofile(dir.."/roster.lua")
extra.set_object_validator(native.valid_object)
local M = {version="0.1.18",core=core,native=native,extra=extra,groups=groups}
local state, current, saved_dir, ledger_path, blocked, saving
local ready_path,ready_slots=nil,{}
local prepared_world,prepared_slot
local prepared_names={}
local activated_world, first_load = nil,true
local hooked = {}
local prior_targets = {}
local settled_plans=setmetatable({},{__mode="k"})
local refunded_plans=setmetatable({},{__mode="k"})
local completion_job,completion_sequence=nil,0
local completion_results={}
local activation_requested=true
local skill_scan_requested=true
local skill_births={}
local skill_save_error
local native_save_wait
local story_receipt
local story_stages={Stage1="Lab2",Stage2="Lab3",Stage3="Lab4",Stage4="Lab5"}
local function log(s) print("[AllAttributes] "..tostring(s).."\n") end
local function valid(o) return native.valid_object(o) end
local function text(v) if type(v)=="string" then return v end return v:ToString() end
local function unbox(value)
 local ok,out=pcall(function()return value:get()end)
 return ok and out or value
end
local function read(path)
 local f=fileio.open(path,"rb");if not f then return nil end
 local s=f:read("*a");f:close();return s
end
local function write(path,bytes)
 local f,err=fileio.open(path,"wb");if not f then return nil,err end
 local ok,why=f:write(bytes);if not ok then f:close();return nil,why end
 local flushed,flush_error=f:flush()
 local closed,close_error=f:close()
 if not flushed then return nil,flush_error end
 if not closed then return nil,close_error end
 return true
end
local function atomic_write(bytes)
 local ok,err=write(ledger_path..".tmp",bytes);if not ok then return nil,err end
 local previous=read(ledger_path)
 if previous then
  local backed,why=write(ledger_path..".bak",previous);if not backed then return nil,why end
  local removed,why2=fileio.remove(ledger_path);if not removed then return nil,why2 end
 end
 local renamed,why=fileio.rename(ledger_path..".tmp",ledger_path)
 if not renamed and previous then write(ledger_path,previous) end
 if not renamed then return nil,why end
 return true
end
local function load_ready()
 local bytes=read(ready_path)
 if not bytes then return true end
 local first=true
 for line in bytes:gmatch("[^\r\n]+")do
  if first then if line~="EAA_UNINSTALL_READY_V1" then return nil,"invalid_uninstall_marker" end;first=false
  else
   local slot,fp=line:match("^SLOT\t([A-Za-z0-9_-]+)\t([a-f0-9]+:[a-f0-9]+)$")
   if not slot or #fp~=129 or fp:sub(65,65)~=":" then return nil,"invalid_uninstall_marker" end
   ready_slots[slot]=fp
  end
 end
 return true
end
local function save_ready()
 local names={};for slot in pairs(ready_slots)do names[#names+1]=slot end;table.sort(names)
 local rows={"EAA_UNINSTALL_READY_V1"}
 for _,slot in ipairs(names)do rows[#rows+1]="SLOT\t"..slot.."\t"..ready_slots[slot]end
 local ok,err=write(ready_path..".tmp",table.concat(rows,"\n").."\n");if not ok then return nil,err end
 local old=read(ready_path)
 if old then
  local backed,why=write(ready_path..".bak",old);if not backed then return nil,why end
  local removed,why2=fileio.remove(ready_path);if not removed then return nil,why2 end
 end
 local renamed,why=fileio.rename(ready_path..".tmp",ready_path)
 if not renamed and old then write(ready_path,old)end
 return renamed,why
end
local function clone(t) if type(t)~="table" then return t end local r={};for k,v in pairs(t) do r[k]=clone(v) end;return r end
local function fingerprint(slot,suffix)
 if not slot:match("^[A-Za-z0-9_-]+$") then return nil,"unsafe_save_slot" end
 if suffix~=nil and not story_stages[suffix] then return nil,"unsafe_stage_suffix" end
 suffix=suffix or ""
 local a=read(saved_dir.."SaveGames/"..slot..suffix..".sav")
 local b=read(saved_dir.."SaveGames/"..slot.."LevelData"..suffix..".sav")
 if not a or not b then return nil,"native_save_pair_missing" end
 local ok,why=core.validate_native_save(a);if not ok then return nil,"main_"..why end
 ok,why=core.validate_native_save(b);if not ok then return nil,"level_"..why end
 return core.make_fingerprint(sha256(a),sha256(b))
end
local function native_total(ctx)
 local n=0
 for _,field in ipairs(ctx.group.fields) do
  if field and field~="" then n=n+(tonumber(ctx.grid.ColonySetup[field]) or 0) end
 end
 return n
end
local function get_base_context()
 local ps=FindFirstOf("EotUPlayerState")
 local gs=FindFirstOf("EotUGameState")
 local gm=FindFirstOf("EotUGameMode")
 if not valid(ps) or not valid(gs) or not valid(gm) then return nil,"not_campaign_world" end
 local formic=FindFirstOf("EotUFormicariumGameMode")
 local is_formicarium=valid(formic) and formic:GetWorld():GetAddress()==gs:GetWorld():GetAddress()
 if not is_formicarium and (tonumber(gm.NewGamePlusLevel) or 0)<=0 then
  -- The story roster verifies the linked campaign slot and local colony. It
  -- also permits cultivated foreign ants in a first-playthrough story mission.
  local linked=M.roster and M.roster.get_live_context and M.roster.get_live_context()
  if not linked or linked.is_formicarium or not valid(linked.world)
   or linked.world:GetAddress()~=gs:GetWorld():GetAddress()
   or not valid(linked.gm) or linked.gm:GetAddress()~=gm:GetAddress() then
   return nil,"not_linked_story_mission"
  end
 end
 local slot=text(gm.FormicariumName)
 if slot=="" and valid(gm.LevelSetupSave) then slot=text(gm.LevelSetupSave.LinkedFormicSave) end
 if slot=="" then slot=text(ps.FormicGameData.FormicariumSaveSlot) end
 if slot=="" then return nil,"no_formicarium_slot" end
 return {slot=slot,game_state=gs,game_mode=gm,player_state=ps,world=gs:GetWorld():GetAddress(),is_formicarium=is_formicarium}
end
local function verify_prepared(ctx)
 for _,grid in ipairs(FindAllOf("UGTileGrid") or {})do
  if native.is_owned(grid,ctx.game_state) then
   local rows,err=native.read_buff_rows(grid.ColonyBuffs);if not rows then return nil,err end
   for _,row in ipairs(rows)do
    if row.BuffName:lower():sub(1,#native.prefix)==native.prefix:lower() then return nil,"卸载准备后仍有本模组殖群效果" end
   end
  end
 end
 for _,c in ipairs(FindAllOf("Creature") or {})do
  if valid(c) and prepared_names[groups.canonical_name(text(c.CreatureName))] and native.is_owned(c,ctx.game_state) then
   local health,maximum=tonumber(c.Health),tonumber(c.FullHealth)
   if not health or not maximum or health~=health or maximum~=maximum or maximum<=0 then return nil,"单位生命值无法核验" end
   if health>0 and health>maximum+0.00001 then return nil,"单位当前生命仍高于基础上限" end
  end
 end
 return true
end
local function persist(ctx)
 if prepared_world==ctx.world and prepared_slot==ctx.slot then
  local verified,why=verify_prepared(ctx);if not verified then return nil,why end
 end
 local fp,err=fingerprint(ctx.slot);if not fp then return nil,err end
 local previous_fp=state.slots[ctx.slot] and state.slots[ctx.slot].anchor
 local ok,why=core.capture_snapshot(state,ctx.slot,fp);if not ok then return nil,why end
 ok,why=core.save(state,{atomic_write=atomic_write});if not ok then return nil,why end
 if M.skills then
  ok,why=M.skills.on_profile_saved(ctx,fp,previous_fp)
  if not ok then skill_save_error=why;M.skills.suspend(why);skill_scan_requested=true;log('技能存档暂不可用：'..tostring(why))end
 end
 if prepared_world==ctx.world and prepared_slot==ctx.slot and ready_slots[ctx.slot] then
  ready_slots[ctx.slot]=fp
  ok,why=save_ready();if not ok then return nil,why end
 end
 log("保存已绑定："..ctx.slot)
 return fp
end
-- A non-skip SaveFormicarium only creates a SavingOverlay. Its native Tick
-- invokes the save delegate at TickCounter==1 and increments to 2 *after*
-- the delegate returns. Observe that exact new instance, never a time delay
-- or an arbitrary new fingerprint, before binding the resulting files.
local function save_overlays(ctx)
 local found={}
 for _,overlay in ipairs(FindAllOf("SavingOverlayBase") or {})do
  if valid(overlay) then
   local world=overlay:GetWorld()
   if valid(world) and world:GetAddress()==ctx.world then
    found[overlay:GetAddress()]=overlay
   end
  end
 end
 return found
end
local function settle_native_save()
 local wait=native_save_wait
 if not wait then return false end
 local live=get_base_context()
 if not live or live.world~=wait.world or live.slot~=wait.slot
  or live.game_mode:GetAddress()~=wait.mode or not current or current.world~=wait.world then
  return nil,"native_save_context_changed"
 end
 if wait.collecting then return false end
 local overlays=save_overlays(live)
 for address in pairs(wait.overlays)do
  local overlay=overlays[address]
  if not overlay then return nil,"native_save_overlay_disappeared_before_completion" end
  local ticks=tonumber(overlay.TickCounter)
  if not ticks or ticks<2 then return false end
 end
 if state.revision~=wait.revision or state.slots[wait.slot].anchor~=wait.anchor then
  return nil,"native_save_ledger_changed"
 end
 local fp,why=persist(live)
 if not fp then return nil,why end
 native_save_wait=nil
 log("原生保存提示已完成，存档指纹已核验："..live.slot)
 return true
end
local function purchase_save_ready(ctx)
 if native_save_wait then return nil,"原生存档正在保存，请稍候再加点" end
 local fp,why=fingerprint(ctx.slot)
 if not fp then return nil,why end
 if not state or not state.slots[ctx.slot] or fp~=state.slots[ctx.slot].anchor then
  return nil,"存档尚未与扩展记录完成核验，暂不可加点"
 end
 return true
end
local function apply_extra(creature,points)
 local copied=M.slaver_conversion and M.slaver_conversion.has_snapshot(creature)==true
 if M.slaver_balance then
  local balanced,why=M.slaver_balance.apply(creature);if not balanced then return nil,why end
 end
 if M.slaver_runtime then
  local ok,why=M.slaver_runtime.before_attributes(creature);if not ok then return nil,why end
 end
 if M.skills_runtime and not copied then
  local ok,why=M.skills_runtime.before_attributes(creature);if not ok then return nil,why end
 end
 local result,why
 if copied then result={preserved_capture=true}else result,why=extra.apply(creature,points)end
 if M.skills_runtime and not copied then
  local decorated,e=M.skills_runtime.decorate(creature);if not decorated then return nil,e end
 end
 if M.slaver_runtime then
  local decorated,e=M.slaver_runtime.decorate(creature);if not decorated then return nil,e end
 end
 return result,why
end
local function sync(ctx,refresh)
 if prepared_world==ctx.world and prepared_slot==ctx.slot then return true end
 local allocations=state.slots[ctx.slot].points
 local expanded,why=groups.expand(allocations);if not expanded then return nil,why end
 local native_points,extra_targets={},{}
 for name,points in pairs(expanded) do
  native_points[name]={}
  for id,n in pairs(points) do
   if native.by_id[id] and native.by_id[id].supported then native_points[name][id]=n end
   if extra.by_id[id] and extra.by_id[id].supported and n>0 then extra_targets[name]=true end
  end
 end
 -- Native colony buffs also cover future hatchlings. Only the three separate
 -- per-creature attributes need this sweep; retain old targets for removal.
 for name,points in pairs(prior_targets[ctx.world] or {}) do
  for id,n in pairs(points) do
   if extra.by_id[id] and extra.by_id[id].supported and n>0 then extra_targets[name]=true end
  end
 end
 local count=0
 for _,grid in ipairs(FindAllOf("UGTileGrid") or {}) do
  local owned=native.is_owned(grid,ctx.game_state)
  if owned then
   local result,err=native.sync_grid(grid,native_points,ctx.game_state)
   if not result then return nil,err end
   count=count+1
  end
 end
 if count==0 then return nil,"no_owned_colony" end
 if refresh then
  local target_names={}
  for name in pairs(expanded) do target_names[name]=true end
  for name in pairs(prior_targets[ctx.world] or {}) do target_names[name]=true end
  local targets={}
  for _,creature in ipairs(FindAllOf("Creature") or {}) do
   if valid(creature) and target_names[groups.canonical_name(text(creature.CreatureName))] and native.is_owned(creature,ctx.game_state) then targets[#targets+1]=creature end
  end
  local result,err=native.refresh_creatures(targets,ctx.game_state)
  if not result then return nil,err end
  for reason in pairs(result.errors)do if reason~="not_alive" then return nil,"单位属性刷新失败："..reason end end
  log("已刷新玩家单位 "..result.refreshed.."，当前生命保持不变")
 end
 if next(extra_targets) then
  for _,creature in ipairs(FindAllOf("Creature") or {}) do
   if valid(creature) then
    local name=groups.canonical_name(text(creature.CreatureName))
    if extra_targets[name] and native.is_owned(creature,ctx.game_state) then
     local result,err=apply_extra(creature,expanded[name] or {})
     if not result then return nil,err end
    end
   end
  end
  extra.forget_invalid()
 end
 prior_targets[ctx.world]=expanded
 return true
end
local function activate()
 if blocked then return nil,blocked end
 local ctx,err=get_base_context()
 if not ctx then
  if current and M.ui and M.ui.invalidate then M.ui.invalidate("campaign_context_unavailable") end
  return nil,err
 end
 if current and current.slot==ctx.slot and activated_world==ctx.world then return current end
 if current and M.ui and M.ui.invalidate then M.ui.invalidate("campaign_world_or_slot_changed") end
 if M.skills_purchase then
  local recovered,why=M.skills_purchase.recover(ctx);if not recovered then blocked=why;return nil,why end
 end
 if not saved_dir then
  saved_dir=text(StaticFindObject("/Script/Engine.Default__BlueprintPathsLibrary"):ProjectSavedDir()):gsub("\\","/")
  if saved_dir:sub(-1)~="/" then saved_dir=saved_dir.."/" end
  ledger_path=saved_dir.."SaveGames/EAA_AllAttributes_v1.tsv"
  ready_path=saved_dir.."SaveGames/EAA_AllAttributes_v1.uninstall-ready.tsv"
  local ready_ok,ready_error=load_ready();if not ready_ok then blocked=ready_error;return nil,blocked end
  local bytes=read(ledger_path) or read(ledger_path..".tmp") or read(ledger_path..".bak")
  if bytes then state,err=core.decode(bytes);if not state then blocked="ledger_invalid:"..tostring(err);return nil,blocked end
  else state=core.new_state() end
  if read(ledger_path..".pending") then blocked="存在未完成保存的加点记录，请先恢复该次交易";return nil,blocked end
 end
 local fp,why=fingerprint(ctx.slot);if not fp then return nil,why end
 if not state.slots[ctx.slot] then
  local ok,e=core.seed_slot(state,ctx.slot,fp);if not ok then return nil,e end
 else
  local ok,e=core.restore_snapshot(state,ctx.slot,fp)
  if not ok and e=="unknown_fingerprint" then
   ok,e=core.rebind_empty_history(state,ctx.slot,fp)
   if ok then
    ok,e=core.save(state,{atomic_write=atomic_write})
    if ok then log("已校验全部历史无扩展点数，重新绑定原生存档："..ctx.slot) end
   end
  end
  if not ok then blocked="存档与扩展加点记录不匹配："..e;log(blocked);return nil,blocked end
 end
 if ready_slots[ctx.slot] then
  ready_slots[ctx.slot]=nil
  local ok,e=save_ready();if not ok then blocked="无法撤销旧卸载标记："..tostring(e);return nil,blocked end
 end
 prepared_world,prepared_slot=nil,nil
 prepared_names={}
 current,activated_world,first_load=ctx,ctx.world,false
 skill_scan_requested=true
 if M.skills then
  local loaded,why=M.skills.on_profile_loaded(ctx,fp)
  if not loaded then skill_save_error=why;M.skills.suspend(why);log('技能存档暂不可用：'..tostring(why))end
 end
 local ok,e=sync(ctx,true);if not ok then current,activated_world=nil,nil;return nil,e end
 log("已载入扩展加点记录："..ctx.slot)
 return ctx
end
local function resolve_context(widget,verify_save)
 if completion_job then return nil,"正在保存本次加点，请稍候" end
 if blocked then return nil,blocked end
 local live,err=get_base_context()
 if not live then return nil,err end
 if not current or current.world~=live.world or current.slot~=live.slot then
  activation_requested=true;return nil,"游戏正在载入加点记录，请稍候"
 end
 local base=current
 if verify_save then
  local ready,ready_error=purchase_save_ready(base);if not ready then return nil,ready_error end
 else
  -- Setup, ShowDialog and price repaint can all run for one native '+' click.
  -- The active profile is already bound on load/save; displaying it must not
  -- synchronously hash the entire level save again. Payment uses resolve().
  if native_save_wait or saving then return nil,"原生存档正在保存，请稍候再加点" end
  if not state or not state.slots[base.slot] then return nil,"加点记录尚未载入" end
 end
 if not valid(widget) or not valid(widget.OwningTileGrid) then return nil,"widget_grid_missing" end
 local allowed,why=native.is_owned(widget.OwningTileGrid,base.game_state);if not allowed then return nil,why end
 local group,e=groups.resolve(tonumber(widget.Species),tonumber(widget.Subtype),text(widget.CreatureName))
 if not group then return nil,e end
 local ctx={};for k,v in pairs(base) do ctx[k]=v end
 ctx.group,ctx.grid=group,widget.OwningTileGrid
 return ctx
end
local function resolve(widget)return resolve_context(widget,true)end
local function resolve_view(widget)return resolve_context(widget,false)end
local function resolve_group(group_id,tree,prepare_profile)
 if completion_job then return nil,"正在保存本次加点，请稍候" end
 if blocked then return nil,blocked end
 local group=groups.by_id[group_id]
 if not group or not group.supplemental then return nil,"unknown_supplemental_group" end
 local live,why=get_base_context()
 if not live then return nil,why end
 if not live.is_formicarium or live.game_mode.InMission then return nil,"只能在养殖箱中购买改进" end
 if not valid(tree) then return nil,"biology_window_expired" end
 local tree_world=tree:GetWorld()
 if not valid(tree_world) or tree_world:GetAddress()~=live.world then return nil,"biology_world_changed" end
 if native_save_wait or saving then return nil,"原生存档正在保存，请稍候再加点" end
 if not current or current.world~=live.world or current.slot~=live.slot then
  activation_requested=true
  -- The first Biology mount may precede the periodic profile activation.
  -- Finish that one load before painting the list; ordinary reads/quotes do
  -- not request this path and keep their existing payment checks.
  if not prepare_profile then return nil,"游戏正在载入加点记录，请稍候" end
  local prepared,reason=activate();if not prepared then return nil,reason end
  activation_requested=false
 end
 -- Opening a read-only view must not hash the entire level save on the game
 -- thread. The active ledger was verified on load/save. Every actual quote,
 -- debit and commit still checks the current native fingerprint independently.
 if not state or not state.slots[current.slot] then return nil,"加点记录尚未载入" end
 local pc,pc_error=native.get_local_controller(live.game_state)
 if not valid(pc) then return nil,pc_error end
 local grid=unbox(live.game_state:GetTileGridByColonyID(pc:GetColonyID()))
 if not valid(grid) or not native.is_owned(grid,live.game_state) then return nil,"player_colony_unavailable" end
 local ctx={};for k,v in pairs(current)do ctx[k]=v end
 ctx.group,ctx.grid=group,grid
 return ctx
end
local function options(ctx)
 local out={}
 for _,s in ipairs(native.catalog) do
  if s.supported and not ctx.group.native_stats[s.id] then
   local applicable=true
   if ctx.group.id=="Queen" and (s.id=="ResourceHarvest" or s.id=="AttackDamage" or s.id=="AttackSpeed" or s.id=="Piercing" or s.id=="MovementSpeed") then applicable=false end
   if applicable then
   local item=clone(s)
   item.description="累计增加 {Arg1}（每点 {Arg2}）"
   out[#out+1]=item
   end
  end
 end
 for _,s in ipairs(extra.catalog) do
  if not ctx.group.native_stats[s.id] then
   local applicable=false
   for _,c in ipairs(FindAllOf("Creature") or {}) do
    if valid(c) and groups.matches(ctx.group,text(c.CreatureName)) and native.is_owned(c,ctx.game_state) then
     if extra.is_applicable(c,s.id) then applicable=true;break end
    end
   end
   if applicable then
    local item=clone(s)
    item.description=s.id=="Cooldown" and "每点减少 0.5 秒，最低 0.1 秒（扩展规则）" or
     s.id=="MaxDamageTaken" and "每点减少 2；原无上限从最大生命值起算，最低 1（扩展规则）" or "每点增加 2，作用于已有攻击和技能射程"
    out[#out+1]=item
   end
  end
 end
 return out
end
local function balance(ctx)
 return tonumber(ctx.game_state:GetRoyalJellyByColony(ctx.grid.ColonyID))
end
local function plan(ctx,pending)
 if blocked then return nil,blocked end
 if completion_job then return nil,"正在保存本次加点，请稍候" end
 local ready,ready_error=purchase_save_ready(ctx);if not ready then return nil,ready_error end
 if prepared_world==ctx.world and prepared_slot==ctx.slot then return nil,"已准备卸载；本次会话暂停扩展加点" end
 if not ctx.is_formicarium or ctx.game_mode.InMission then return nil,"只能在蚁巢中购买扩展改进" end
 local limits={}
 for _,s in ipairs(options(ctx)) do
  local count=assert(core.get_points(state,ctx.slot,ctx.group.id,s.id))
  local cap=s.native_cap or s.effective_cap
  if s.id=="AreaOfEffectResistance" or s.id=="OutOfCombatEvasion" or s.id=="Piercing" then cap=math.min(cap or 1,1) end
  local limit=core.INT_MAX
  if (s.id=="Cooldown" or s.id=="MaxDamageTaken") and (pending[s.id] or 0)>0 then
   local remaining=0
   for _,c in ipairs(FindAllOf("Creature") or {}) do
    if valid(c) and groups.matches(ctx.group,text(c.CreatureName)) and native.is_owned(c,ctx.game_state) then
     if s.id=="MaxDamageTaken" then
      local value=c.MaxSingleDamage>0 and c.MaxSingleDamage or c.FullHealth
      remaining=math.max(remaining,math.ceil(math.max(0,value-1)/2-0.000001))
     else
      local abilities=c.AbilityList
      local count=abilities:GetArrayNum()
      assert(type(count)=="number" and count>=0 and count%1==0 and count<=2147483647,"invalid ability array length")
      for i=1,count do
       local value=unbox(abilities[i]).Cooldown
       if value>0 then remaining=math.max(remaining,math.ceil(math.max(0,value-0.1)/0.5-0.000001)) end
      end
     end
    end
   end
   limit=count+remaining
  end
  if cap and (pending[s.id] or 0)>0 then
   local maximum=nil
   local names={};for _,n in ipairs(ctx.group.aliases) do names[n]=true end
   for _,c in ipairs(FindAllOf("Creature") or {}) do
    if valid(c) and names[groups.canonical_name(text(c.CreatureName))] and native.is_owned(c,ctx.game_state) then
     local value=tonumber(c[s.field])
     if value then maximum=math.max(maximum or value,value) end
    end
   end
   if maximum==nil then
    local row_field=({FullHealth="Health",OriginalMaxSpeed="Speed",AOEResistance="AOEResist"})[s.field] or s.field
    local default=StaticFindObject("/Script/EotU.Default__Creature")
    local expanded,expand_error=groups.expand(state.slots[ctx.slot].points)
    if not expanded then return nil,expand_error end
    for _,name in ipairs(ctx.group.aliases) do
     local actor_points=expanded[groups.canonical_name(name)] or {}
     for level=1,3 do
      local success={}
      local stats=default:GetCreatureStats(FName(name),ctx.game_state,level,ctx.grid.ColonyID,success)
      local value=stats and tonumber(stats[row_field])
      if value then maximum=math.max(maximum or value,value+(actor_points[s.id] or 0)*s.per_point) end
     end
    end
   end
   if maximum==nil then return nil,"无法确认该兵种的属性上限，未扣款" end
   limit=count+math.max(0,math.floor((cap-maximum+0.000001)/s.per_point))
  end
  limits[s.id]=limit
 end
 return core.plan_purchase(state,{slot=ctx.slot,species=ctx.group.id,native_total=native_total(ctx),balance=balance(ctx),pending=pending,limits=limits})
end
local function pending_bytes(ctx,p,before,after)
 local names={};for stat in pairs(p.points_after)do names[#names+1]=stat end;table.sort(names)
 local journal=table.concat({"EAA_PENDING_V1",ctx.slot,ctx.group.id,tostring(p.cost),tostring(before),tostring(after),p.anchor},"\t").."\n"
 for _,stat in ipairs(names)do journal=journal..stat.."\t"..p.points_after[stat].."\n"end
 return journal
end
local function clear_own_pending(expected)
 local bytes=read(ledger_path..".pending")
 if bytes==nil then return true end
 if bytes~=expected then return nil,"pending_record_changed" end
 local removed,why=fileio.remove(ledger_path..".pending")
 if not removed or read(ledger_path..".pending")~=nil then return nil,why or "pending_remove_not_verified" end
 return true
end
local function commit(ctx,p,before,after)
 if blocked then return nil,blocked end
 if settled_plans[p] then return nil,"该交易已经处理" end
 local journal=pending_bytes(ctx,p,before,after)
 local function refund_once(reason)
  if refunded_plans[p] then return nil,"该交易已经返还" end
  if before==p.balance and after==before-p.cost and balance(ctx)==after then
   ctx.game_state:GivePlayerRoyalJelly(ctx.grid.ColonyID,p.cost)
   if balance(ctx)~=before then blocked="返还金额核验失败，已停止后续交易";return nil,blocked end
   refunded_plans[p]=true
   local cleared,clear_error=clear_own_pending(journal)
   if not cleared then blocked="金额已返还，但付款记录未能安全清理："..tostring(clear_error);return nil,blocked end
   log("交易已安全撤回："..tostring(reason))
   return nil,"交易未完成，蜂王浆已返还："..tostring(reason),{rolled_back=true,balance=before}
  end
  blocked="扣款状态无法安全核对，已停止后续交易："..tostring(reason)
  return nil,blocked
 end
 local checkpoint=clone(state)
 local ok,err=core.commit_purchase(state,p,{paid=true,before=before,after=after,native_total=native_total(ctx)})
 if not ok then return refund_once(err) end
 ok,err=write(ledger_path..".pending",journal)
 if ok then ok,err=sync(ctx,true) end
 if not ok then
  state=checkpoint
  -- Roll back every alias touched by the attempted group, including its first
  -- ever purchase when the old ledger contains no such group yet.
  prior_targets[ctx.world]=prior_targets[ctx.world] or {}
  for _,name in ipairs(ctx.group.aliases)do prior_targets[ctx.world][name]=prior_targets[ctx.world][name] or {} end
  local restored,restore_error=sync(ctx,true)
  if not restored then blocked="属性补偿未能核验，付款记录已保留："..tostring(restore_error);return nil,blocked end
  return refund_once(err)
 end
 local old_fp=state.slots[ctx.slot].anchor
 saving=true
 local saved,save_err=pcall(function() ctx.game_mode:SaveFormicarium(false,true) end)
 saving=false
 if not saved then blocked="原生存档保存失败，交易记录已保留："..tostring(save_err);return nil,blocked end
 local new_fp,fp_err=fingerprint(ctx.slot)
 if not new_fp or new_fp==old_fp then blocked="原生存档未确认更新，交易记录已保留："..tostring(fp_err);return nil,blocked end
 local persisted,persist_err=persist(ctx)
 if not persisted then blocked="扩展记录保存失败，交易记录已保留："..tostring(persist_err);return nil,blocked end
 local cleared,clear_error=clear_own_pending(journal)
 if not cleared then blocked="存档已完成，但付款记录未能安全清理："..tostring(clear_error);return nil,blocked end
 settled_plans[p]=true
 log("购买成功 "..ctx.group.id.."："..p.quantity.." 点，消耗 "..p.cost.." 蜂王浆")
 return true
end
local function refund_native(ctx,colony,before,cost)
 local live=get_base_context()
 if not live or live.slot~=ctx.slot or live.world~=ctx.world or not valid(ctx.grid)
  or ctx.game_state:GetAddress()~=live.game_state:GetAddress() or ctx.grid.ColonyID~=colony
  or not native.is_owned(ctx.grid,ctx.game_state) then return nil,"native_recovery_context_changed" end
 local actual=tonumber(ctx.game_state:GetRoyalJellyByColony(colony))
 if actual==before then return true,"no_debit" end
 if actual~=before-cost then return nil,"native_recovery_balance_changed" end
 ctx.game_state:GivePlayerRoyalJelly(colony,cost)
 if tonumber(ctx.game_state:GetRoyalJellyByColony(colony))~=before then return nil,"native_refund_not_verified" end
 return true,"refunded"
end
local function after_native_purchase(ctx)
 local live=get_base_context()
 if not live or not ctx or live.slot~=ctx.slot or live.world~=ctx.world
  or not valid(ctx.grid) or not native.is_owned(ctx.grid,live.game_state)
  or not ctx.group or groups.by_id[ctx.group.id]~=ctx.group then return nil,"native_refresh_context_changed" end
 local synced,why=sync(live,false);if not synced then return nil,why end
 local targets={}
 if ctx.group.id=="Queen" then
  -- The original game has one authoritative queen per colony. Other queens
  -- in diagnostic fixtures must not broaden this production rule.
  local queen=ctx.grid.ColonyQueen
  if valid(queen) and native.is_owned(queen,live.game_state) then targets[1]=queen end
 else
  for _,creature in ipairs(FindAllOf("Creature") or {})do
   if valid(creature) and groups.by_creature[groups.canonical_name(text(creature.CreatureName))]==ctx.group
    and native.is_owned(creature,live.game_state) then targets[#targets+1]=creature end
  end
 end
 local refreshed,err=native.refresh_creatures(targets,live.game_state)
 if not refreshed then return nil,err end
 for reason in pairs(refreshed.errors)do if reason~="not_alive"then return nil,reason end end
 if prepared_world~=ctx.world then
  local points=(state.slots[ctx.slot].points or {})[ctx.group.id] or {}
  for _,creature in ipairs(targets)do
   if valid(creature) and creature.Health>0 then
    local applied,e=apply_extra(creature,points);if not applied then return nil,e end
   end
  end
 end
 log("原生加点已刷新兵种 "..ctx.group.id.."："..refreshed.refreshed.."，当前生命保持不变")
 return true,{group=ctx.group.id,refreshed=refreshed.refreshed}
end
-- Blueprint script hooks hold UE4SS's global callback mutex. SaveFormicarium
-- can wait for an asynchronous UObject constructor that needs that mutex.
-- These jobs contain only primitive evidence and the original pure core plan;
-- the EngineTick consumer resolves fresh objects after the hook has returned.
local function completion_identity(ctx)
 local live,why=get_base_context()
 if not live or not ctx or live.slot~=ctx.slot or live.world~=ctx.world
  or not valid(ctx.grid) or not ctx.group or groups.by_id[ctx.group.id]~=ctx.group
  or not native.is_owned(ctx.grid,live.game_state)
  or ctx.game_state:GetAddress()~=live.game_state:GetAddress() then return nil,why or "completion_context_changed" end
 return {slot=ctx.slot,world=ctx.world,group=ctx.group.id,colony=ctx.grid.ColonyID,
  grid=ctx.grid:GetAddress(),game_state=ctx.game_state:GetAddress()}
end
local function queue_commit(ctx,p,before,after)
 if blocked then return nil,blocked end
 if completion_job then return nil,"completion_already_pending" end
 local ready,ready_error=purchase_save_ready(ctx);if not ready then return nil,ready_error end
 local job,why=completion_identity(ctx);if not job then return nil,why end
 if type(p)~="table" or p.slot~=ctx.slot or p.species~=ctx.group.id or p.balance~=before
  or type(p.cost)~="number" or after~=before-p.cost or balance(ctx)~=after
  or p.native_total~=native_total(ctx) or p.revision~=state.revision
  or p.anchor~=state.slots[ctx.slot].anchor then return nil,"queued_receipt_mismatch" end
 if read(ledger_path..".pending") then return nil,"pending_journal_already_present" end
 local journal=pending_bytes(ctx,p,before,after)
 local ok,err=write(ledger_path..".pending",journal)
 if not ok or read(ledger_path..".pending")~=journal then
  blocked="排队付款记录无法安全保存："..tostring(err);return nil,blocked
 end
 completion_sequence=completion_sequence+1
 job.id,job.kind,job.phase=completion_sequence,"extra","queued"
 job.plan,job.before,job.after=p,before,after
 completion_job=job
 return job.id
end
local function queue_native_refresh(ctx,receipt)
 if blocked then return nil,blocked end
 if completion_job then return nil,"completion_already_pending" end
 local job,why=completion_identity(ctx);if not job then return nil,why end
 local total,e=core.total_points(state,ctx.slot,ctx.group.id,native_total(ctx))
 if not total or type(receipt)~="table" or total~=receipt.expected_total
  or type(receipt.before)~="number" or type(receipt.after)~="number"
  or receipt.before<=receipt.after or balance(ctx)~=receipt.after then return nil,e or "native_completion_receipt_mismatch" end
 completion_sequence=completion_sequence+1
 job.id,job.kind,job.phase=completion_sequence,"native","queued"
 job.expected_total,job.before,job.after=receipt.expected_total,receipt.before,receipt.after
 completion_job=job
 return job.id
end
local function poll_completion(id)
 if completion_results[id] then return completion_results[id] end
 local job=completion_job
 if not job or job.id~=id then return nil,"unknown_completion" end
 if job.phase~="queued" then return nil,"completion_in_progress" end
 job.phase="executing"
 local ok,result=pcall(function()
  local ctx,why=get_base_context();assert(ctx,why)
  assert(ctx.slot==job.slot and ctx.world==job.world and ctx.game_state:GetAddress()==job.game_state,"queued_world_or_slot_changed")
  local grid=ctx.game_state:GetTileGridByColonyID(job.colony)
  assert(valid(grid) and grid:GetAddress()==job.grid and native.is_owned(grid,ctx.game_state),"queued_colony_changed")
  ctx.grid,ctx.group=grid,assert(groups.by_id[job.group])
  assert(balance(ctx)==job.after,"queued_balance_changed")
  if job.kind=="native" then
   assert(core.total_points(state,ctx.slot,ctx.group.id,native_total(ctx))==job.expected_total,"native_ranks_changed_before_refresh")
   local refreshed,err=after_native_purchase(ctx);assert(refreshed,err)
   return {phase="committed",kind="native",balance=job.after}
  end
  assert(fingerprint(ctx.slot)==job.plan.anchor,"queued_native_save_changed")
  local done,err,recovery=commit(ctx,job.plan,job.before,job.after)
  if done then return {phase="committed",kind="extra",balance=job.after} end
  if recovery and recovery.rolled_back and recovery.balance==job.before and balance(ctx)==job.before then
   return {phase="rolled_back",kind="extra",balance=job.before,reason=err}
  end
  return {phase="recovery_required",kind="extra",reason=tostring(err)}
 end)
 if not ok then result={phase="recovery_required",kind=job.kind,reason=tostring(result)} end
 if result.phase=="recovery_required" then
  blocked="加点收尾未完成，已保留付款记录："..tostring(result.reason)
  log(blocked)
 end
 job.phase=result.phase
 completion_results[id]=result
 completion_results[id-32]=nil
 completion_job=nil
 return result
end
local function tick_context()
 -- A Scoreboard stage transition is synchronous. A receipt surviving until
 -- another game-thread frame cannot authorize a later, unrelated disk change.
 if story_receipt then
  story_receipt=nil
  log("剧情阶段保存观察未完成，未重新绑定存档")
 end
 if completion_job or blocked then return false end
 if native_save_wait then
  local done,why=settle_native_save()
  if done==nil then blocked="原生保存未能安全核验："..tostring(why);log(blocked);return false end
  if done then return true end
  return false
 end
 local live=get_base_context()
 if not live then
  if current and M.ui then M.ui.invalidate("campaign_context_unavailable")end
  current,activated_world=nil,nil
  activation_requested=true;return false
 end
 if activation_requested or not current or current.world~=live.world or current.slot~=live.slot then
  local was=current
  local ctx,why=activate()
  activation_requested=ctx==nil
  if not ctx then return false,why end
  return was~=ctx
 end
 return false
end
M.api={valid_object=native.valid_object,resolve=resolve,resolve_view=resolve_view,resolve_group=resolve_group,options=options,points=function(c,id)return assert(core.get_points(state,c.slot,c.group.id,id))end,
 total=function(c)return assert(core.total_points(state,c.slot,c.group.id,native_total(c)))end,
 next_cost=core.next_cost,cost_for=core.cost_for,balance=balance,plan=plan,commit=commit,refund_native=refund_native,
 after_native_purchase=after_native_purchase,queue_commit=queue_commit,queue_native_refresh=queue_native_refresh,
 poll_completion=poll_completion,tick_context=tick_context,
 needs_context_tick=function()return native_save_wait~=nil or story_receipt~=nil end,error=log}
M.get_state=function()return state end
M.activate=activate
M.sync=function(refresh)return current and sync(current,refresh)end
M.get_current=function()return current end
M.get_fingerprint=fingerprint
M.ui=ui.install(M.api)
_G.AllAttributes=M
local function prepare_uninstall()
 if completion_job then return nil,"正在保存本次加点，请稍候" end
 if native_save_wait then return nil,"原生存档正在保存，请完成后再准备卸载" end
 local ctx,err=activate();if not ctx then return nil,err end
 if not ctx.is_formicarium or ctx.game_mode.InMission then return nil,"请先返回蚁巢再准备卸载" end
 local session=M.ui.get_active()
 if not session then return nil,"请先在小幅改进面板按 F6 打开扩展属性" end
 if session.payment then return nil,"交易尚未完成，请勿卸载" end
 for i=1,4 do if session.widget["Value"..i.."Change"]~=0 then return nil,"请先确认或撤回待加点，再按 F8" end end
 if M.roster then local stopped,stop_error=M.roster.stop();if not stopped then return nil,stop_error end end
 if M.skills_runtime then local stopped,stop_error=M.skills_runtime.stop();if not stopped then return nil,stop_error end end
 for _,service in ipairs({M.slaver_balance,M.slaver_objectives,M.slaver_food,M.slaver_runtime,M.slaver_medical,M.slaver_native,M.slaver_treatment,M.slaver_damage_guard,M.slaver_controls_ui})do
  if service then local stopped,stop_error=service.stop();if not stopped then return nil,stop_error end end
 end
 local expanded,why=groups.expand(state.slots[ctx.slot].points);if not expanded then return nil,why end
 local targets={}
 for _,c in ipairs(FindAllOf("Creature") or {})do
  if valid(c) and expanded[groups.canonical_name(text(c.CreatureName))] and native.is_owned(c,ctx.game_state) then
   local restored,e=extra.restore(c);if not restored then return nil,e end
   targets[#targets+1]=c
  end
 end
 for _,g in ipairs(FindAllOf("UGTileGrid") or {})do
  if native.is_owned(g,ctx.game_state)then local removed,e=native.sync_grid(g,{},ctx.game_state);if not removed then return nil,e end end
 end
 local refreshed,e=native.refresh_creatures(targets,ctx.game_state);if not refreshed then return nil,e end
 for reason in pairs(refreshed.errors)do if reason~="not_alive" then return nil,"单位清理失败："..reason end end
 -- Suppress subsequent polls and quotes for this world before writing native
 -- saves, so no new hatch or save callback can reapply our effects.
 prepared_world,prepared_slot=ctx.world,ctx.slot
 prepared_names=expanded
 local verified,verify_error=verify_prepared(ctx);if not verified then return nil,verify_error end
 saving=true
 local saved,save_error=pcall(function()ctx.game_mode:SaveFormicarium(false,true)end)
 saving=false
 if not saved then return nil,"准备卸载保存失败："..tostring(save_error) end
 local fp,persist_error=persist(ctx);if not fp then return nil,persist_error end
 ready_slots[ctx.slot]=fp
 local marked,mark_error=save_ready();if not marked then return nil,mark_error end
 M.ui.close()
 if M.foreign_ui then M.foreign_ui.stop()end
 local message="本蚁巢已准备卸载：请退出游戏后运行卸载。已买点数保留，蜂王浆不退还。"
 M.ui.show_message(message)
 log(message.." 槽位="..ctx.slot.."，处理单位="..refreshed.refreshed)
 return true
end
M.prepare_uninstall=prepare_uninstall
M.api.prepare_uninstall=prepare_uninstall
local roster_catalog=dofile(dir.."/roster_catalog.lua")
M.skills=dofile(dir.."/skills.lua").install({fileio=fileio,native=native,state=dofile(dir.."/skills_state.lua"),
 fingerprint=fingerprint,log=log,
 get_context=function()return M.roster and M.roster.get_live_context()end,
 get_mission_choices=function(ctx)return M.roster and M.roster.custom_skill_choices(ctx)end,
 is_ready=function(ctx)return current and current.slot==ctx.slot and not completion_job and not native_save_wait and not saving and not blocked end,
 on_change=function()skill_scan_requested=true end,
 quote_home=function(...)if M.skills_purchase then return M.skills_purchase.quote(...)end;return{can_purchase=false,reason='技能交易尚未就绪'}end,
 purchase_home=function(...)if M.skills_purchase then return M.skills_purchase.request(...)end;return nil,'技能交易尚未就绪'end,
 purchase_result=function(id)return M.skills_purchase and M.skills_purchase.result(id)or{phase='failed',error='技能交易尚未就绪'}end})
M.skills_runtime=dofile(dir.."/skills_runtime.lua").install({native=native,log=log,
 get_context=function()return M.roster and M.roster.get_live_context()end,
 watch_damage=function(creature)return M.slaver_medical and M.slaver_medical.watch_skill_damage(creature)end,
 get_choices=function(creature)return M.skills.get_choices(creature)end})
M.roster=roster.install({fileio=fileio,native=native,groups=groups,sha256=sha256,
 custom_skills=M.skills,
 catalog=roster_catalog,state=dofile(dir.."/roster_state.lua"),
 ui=dofile(dir.."/roster_ui.lua"),runtime=dofile(dir.."/roster_runtime.lua"),
 challenge=dofile(dir.."/roster_challenge.lua"),
 home=dofile(dir.."/roster_home.lua"),
 validate_native_save=core.validate_native_save,log=log,
 is_save_settled=function()return not native_save_wait and not completion_job and not saving and not blocked end,
 is_home_ready=function(ctx)return current and current.is_formicarium and current.slot==ctx.slot
  and valid(ctx.world) and current.world==ctx.world:GetAddress()end,
  sync_attributes=function()skill_scan_requested=true;if current then sync(current,false)end end,
 points_signature=function() return state and sha256(assert(core.encode(state)))or"not_loaded" end})
M.foreign_ui=dofile(dir.."/foreign_ui.lua").install({native=native,groups=groups,ui=M.ui,catalog=roster_catalog,
  custom_skills=M.skills,
 resolve_group=resolve_group,log=log})
-- One world-entry enumeration plus native birth notifications maintains the
-- transport registry. Ordinary gameplay never rescans the world each frame.
local slaver_candidates,slaver_births,slaver_rebuilds,slaver_world={},{},{},nil
local colony_class
-- Share only this synchronous update's context. Battle/input callbacks outside
-- the update still resolve the live world; no UObject context crosses a tick.
local slaver_tick_context
local function slaver_context()
 if slaver_tick_context then return slaver_tick_context end
 return M.roster and M.roster.get_live_context()
end
local function slaver_candidate_list()
 local ctx=slaver_context();local out={}
 if not ctx then return out end
 local world=native.world_id(ctx.gs)
 for id,c in pairs(slaver_candidates)do
  if valid(c)and native.world_id(c)==world and native.is_owned(c,ctx.gs)and c.Health>0 then out[#out+1]=c
  else slaver_candidates[id]=nil end
 end
 return out
end
M.slaver_damage_guard=dofile(dir.."/slaver_damage_guard.lua").install{native=native,verified=true}
M.slaver_conversion=dofile(dir.."/slaver_conversion.lua").install{native=native,verified=true}
M.slaver_balance=dofile(dir.."/slaver_balance.lua").install{native=native,log=log,get_context=slaver_context,preview=true,
 has_snapshot=function(c)return M.slaver_conversion.has_snapshot(c)end}
M.slaver_treatment=dofile(dir.."/slaver_conversion_animation.lua").install{native=native,log=log,get_context=slaver_context}
-- Captured individuals already contain their original cultivation. Buying
-- the same species in our colony must not multiply that snapshot a second time.
local refresh_uncaptured_creature=native.refresh_creature
native.refresh_creature=function(c,gs)
 if M.slaver_conversion.has_snapshot(c)==true then
  return {preserved_capture=true,health_before=c.Health,health_after=c.Health,
   full_health_before=c.FullHealth,full_health_after=c.FullHealth}
 end
 local result,why=refresh_uncaptured_creature(c,gs)
 if not result then return nil,why end
 local balanced,e=M.slaver_balance.apply(c);if not balanced then return nil,e end
 -- The original refresh clamps HP to the temporary unadjusted native maximum.
 -- Restore its recorded HP only after the tier-two maximum is back in place.
 if balanced.changed then
  c.Health=math.min(result.health_before,c.FullHealth)
  result.health_after=c.Health;result.full_health_after=c.FullHealth
 end
 return result
end
M.slaver_native=dofile(dir.."/slaver_native.lua").install{native=native,log=log,
 get_context=slaver_context,candidates=slaver_candidate_list,verified=true,colony_control_verified=false,
 get_choices=function(c,id)return M.skills.get_choices(c,id)end,
 conversion=M.slaver_conversion,treatment=M.slaver_treatment,
 on_slave_ready=function(c)
  if valid(c)then slaver_candidates[tostring(c:GetAddress())]=c end
  if M.slaver_runtime then M.slaver_runtime.observe(c)end
  if M.slaver_medical then M.slaver_medical.observe(c)end
 end}
M.slaver_medical=dofile(dir.."/slaver_medical.lua").install{native=native,log=log,
 get_context=slaver_context,adapter=M.slaver_native}
M.slaver_medical.set_skill_damage_handler(function(...)return M.skills_runtime.on_damage(...)end)
M.slaver_runtime=dofile(dir.."/slaver_runtime.lua").install{native=native,log=log,
 get_context=slaver_context,get_choices=function(c,id)return M.skills.get_choices(c,id)end,
 adapter=M.slaver_native,damage_guard=M.slaver_damage_guard,damage_events=M.slaver_medical,aura_radius=250,medical_delegate=true}
M.slaver_controls_ui=dofile(dir.."/slaver_controls_ui.lua").install{native=native,log=log,
 adapter=M.slaver_native,get_context=slaver_context}
M.slaver_food=dofile(dir.."/slaver_food.lua").install{native=native,log=log,
 adapter=M.slaver_native,get_context=slaver_context}
M.slaver_objectives=dofile(dir.."/slaver_objectives.lua").install{native=native,log=log,
 adapter=M.slaver_native,get_context=slaver_context}
local function observe_slaver_creature(c,ctx)
 if not valid(c)or native.world_id(c)~=native.world_id(ctx.gs)then return end
 M.slaver_conversion.request(c)
 local balanced,why=M.slaver_balance.apply(c);if not balanced then log(why)end
 if not valid(colony_class)then colony_class=StaticFindObject('/Script/EotU.ColonyCreature')end
 if native.is_owned(c,ctx.gs)and((valid(colony_class)and c:IsA(colony_class))or M.slaver_native.is_active_slave(c))then
  slaver_candidates[tostring(c:GetAddress())]=c
 end
 M.slaver_runtime.observe(c)
 M.slaver_medical.observe(c)
end
function M.reset_slaver_cache()
 local ok,why=M.slaver_balance.reset_cache();if not ok then return nil,why end
 ok,why=M.slaver_food.reset_cache();if not ok then return nil,why end
 ok,why=M.slaver_objectives.reset_cache();if not ok then return nil,why end
 ok,why=M.slaver_runtime.reset_cache();if not ok then return nil,why end
 ok,why=M.slaver_native.reset_cache();if not ok then return nil,why end
 ok,why=M.slaver_treatment.reset_cache();if not ok then return nil,why end
 M.slaver_medical.reset_cache()
 slaver_candidates,slaver_births,slaver_rebuilds,slaver_world={},{},{},nil
 return true
end
function M.tick_slaver()
 if slaver_tick_context then return end -- A nested native callback cannot start a second update.
 local ctx=slaver_context();if not ctx then return end
 slaver_tick_context=ctx
 local completed,failure=pcall(function()
 local world=native.world_id(ctx.gs)
 if slaver_world~=world then
  local ok,why=M.reset_slaver_cache();assert(ok,why)
  slaver_world=world
  for _,c in ipairs(FindAllOf('Creature')or{})do observe_slaver_creature(c,ctx)end
 end
 local births=slaver_births;slaver_births={}
 for _,c in pairs(births)do observe_slaver_creature(c,ctx)end
 local rebuilt=slaver_rebuilds;slaver_rebuilds={}
 for _,c in pairs(rebuilt)do
  if valid(c)and native.world_id(c)==world and M.slaver_conversion.has_snapshot(c)==true then
   local ok,why=M.slaver_conversion.restore(c)
   if ok==false and why=='slave_copy_assets_pending'then
    M.slaver_conversion.request(c)
    slaver_rebuilds[tostring(c:GetAddress())]=c
   else assert(ok,why)end
  end
 end
 -- One queued counterpart per update, outside synchronous attack hooks.
 local preloaded,why=M.slaver_conversion.preload_step(1);assert(preloaded,why)
 M.slaver_runtime.tick(ctx.gs:GetLevelTime())
 if M.slaver_balance then local ok,why=M.slaver_balance.tick();assert(ok,why)end
 if M.slaver_objectives then M.slaver_objectives.tick()end
 if M.slaver_controls_ui then M.slaver_controls_ui.tick()end
 if M.slaver_food then M.slaver_food.tick(ctx.gs:GetLevelTime())end
 end)
 slaver_tick_context=nil
 if not completed then error(failure,0)end
end
if type(NotifyOnNewObject)=='function'then
 NotifyOnNewObject('/Script/EotU.Creature',function(c)
  ExecuteInGameThreadAfterFrames(2,function()
   if valid(c)then slaver_births[tostring(c:GetAddress())]=c end
  end)
 end)
end
M.skills_purchase=dofile(dir.."/skills_purchase.lua").install({fileio=fileio,sha256=sha256,log=log,
 begin_hash_scope=begin_hash_scope,end_hash_scope=end_hash_scope,
 save_rotates_backups=false,
 saved_dir=function()return saved_dir or text(StaticFindObject('/Script/Engine.Default__BlueprintPathsLibrary'):ProjectSavedDir())end,
 get_context=function()
  if blocked or completion_job or native_save_wait or saving or not current then return nil end
  local ctx=M.roster.get_live_context()
  if ctx and ctx.slot==current.slot and ctx.world:GetAddress()==current.world then return ctx end
 end,
 fingerprint=fingerprint,balance=function(ctx)
  local gs=ctx.gs or ctx.game_state
  local grid=ctx.grid or gs:GetTileGridByColonyID(native.get_local_controller(gs):GetColonyID())
  return gs:GetRoyalJellyByColony(grid.ColonyID)
 end,
 set_balance=function(ctx,value)
  local gs=ctx.gs or ctx.game_state
  local grid=ctx.grid or gs:GetTileGridByColonyID(native.get_local_controller(gs):GetColonyID())
  local before=gs:GetRoyalJellyByColony(grid.ColonyID)
  if value<before then gs:SpendPlayerRoyalJelly(grid.ColonyID,before-value)
  elseif value>before then gs:GivePlayerRoyalJelly(grid.ColonyID,value-before)end
  return gs:GetRoyalJellyByColony(grid.ColonyID)==value
 end,
 save_native=function(ctx)
  if saving or completion_job or native_save_wait then return nil,'其他保存尚未完成'end
  saving=true
  -- NoBackup skips only native backup rotation, not the profile/level save.
  -- The skill transaction already retains both original files in its journal.
  local ok,why=pcall(function()(ctx.gm or ctx.game_mode):SaveFormicarium(true,true)end)
  saving=false
  return ok,why
 end,
 persist=function(ctx)
  if not current or current.slot~=ctx.slot then return nil,'技能保存的蚁巢已改变'end
  local fp,why=persist(current)
  if skill_save_error then return nil,skill_save_error end
  return fp,why
 end,
 reset=function(ctx)
  if ledger_path then
   local bytes=read(ledger_path)
   if bytes then
    local decoded,why=core.decode(bytes);if not decoded then return nil,why end;state=decoded
   else
    state=core.new_state()
   end
   local fp,why=fingerprint(ctx.slot);if not fp then return nil,why end
   local restored,e
   if state.slots[ctx.slot]then restored,e=core.restore_snapshot(state,ctx.slot,fp)
   else restored,e=core.seed_slot(state,ctx.slot,fp)end
   if not restored then return nil,e end
  end
  local ok,why=M.skills.reload();if not ok then return nil,why end
  skill_save_error=nil
  for _,creature in ipairs(FindAllOf('TrapjawAnt_C')or{})do
   if valid(creature)then local restored,e=M.skills_runtime.before_attributes(creature);if not restored then return nil,e end end
  end
  M.skills_runtime.reset_cache();skill_scan_requested=true
  local reset,err=M.reset_slaver_cache();if not reset then return nil,err end
  return true
 end})

local function safe_hook(path,pre,post)
 local ok,a,b=pcall(RegisterHook,path,pre,post)
 if ok then hooked[#hooked+1]={path,a,b} else log("无法注册钩子 "..path..": "..a) end
end
local ng_paths={
 "/Game/UI/InGame/FormicariumUI/FormicLevelSetup2.FormicLevelSetup2_C:ActivateNewGamePlus",
 "/Game/UI/InGame/FormicariumUI/GatewayButton2.GatewayButton2_C:ConfirmedNewGamePlus",
 "/Game/UI/InGame/FormicariumUI/HeathlandsLevelsSection.HeathlandsLevelsSection_C:ConfirmedNewGamePlus",
}
local ng_registered={}
local story_registered={}
local function same_points(a,b)
 for group,points in pairs(a)do
  if type(b[group])~="table" then return false end
  for stat,n in pairs(points)do if b[group][stat]~=n then return false end end
  for stat in pairs(b[group])do if points[stat]==nil then return false end end
 end
 for group in pairs(b)do if a[group]==nil then return false end end
 return true
end
local function finish_story_transition(receiver)
 local receipt=story_receipt
 if not receipt then return end
 story_receipt=nil -- nested wrapper/Ubergraph callbacks may commit only once
 local ok,result,why=pcall(function()
  local widget=unbox(receiver)
  if saving or blocked or completion_job or native_save_wait then return nil,"stage_save_in_progress" end
  if state~=receipt.state or current~=receipt.ctx then return nil,"stage_context_changed" end
  if not valid(widget) or widget.FormicariumLevelEnd~=true
   or text(widget.FormicariumLevelFinished)~=story_stages[receipt.suffix] then return nil,"stage_scoreboard_mismatch" end
  local world=widget:GetWorld()
  if not valid(world) or world:GetAddress()~=receipt.ctx.world then return nil,"stage_scoreboard_world_changed" end
  if not same_points(state.slots[receipt.ctx.slot].points,receipt.points) then return nil,"stage_points_changed" end
  if fingerprint(receipt.ctx.slot,receipt.suffix)~=receipt.stage_fp then return nil,"stage_checkpoint_changed" end
  local fp,e=persist(receipt.ctx)
  if not fp then return nil,e end
  log("剧情阶段继承已绑定："..receipt.ctx.slot.." / "..receipt.suffix)
  return true
 end)
 if not ok or not result then
  blocked="剧情阶段保存未能安全核验："..tostring(why or result)
  log(blocked)
 end
end
local function ensure_story_hooks()
 local prefix="/Game/UI/InGame/Scoreboard/Scoreboard.Scoreboard_C:"
 for _,name in ipairs({"ExecuteUbergraph_Scoreboard","BndEvt__ButtonOK_K2Node_ComponentBoundEvent_7_OnButtonReleasedEvent__DelegateSignature","ReturnToFormicarium"})do
  local path=prefix..name
  if not story_registered[path] and valid(StaticFindObject(path)) then
   -- Non-/Script/ hooks run AFTER the blueprint. Native Stage save below is
   -- the trusted precondition; never adopt an unknown save from this hook alone.
   local ok,a,b=pcall(RegisterHook,path,function(receiver,entry)
    if name=="ExecuteUbergraph_Scoreboard" then
     local offset=tonumber(unbox(entry))
     if offset~=5199 and offset~=11351 then return end
    end
    finish_story_transition(receiver)
   end)
   if ok then story_registered[path]=true;hooked[#hooked+1]={path,a,b}end
  end
 end
end
local function ensure_ng_hooks()
 for _,path in ipairs(ng_paths)do
  if not ng_registered[path] and valid(StaticFindObject(path)) then
   local ok,a,b=pcall(RegisterHook,path,function()
    -- These synchronous blueprint functions rewrite the SAME primary slot
    -- after SaveFormicarium, then start the asynchronous fade/travel.
    if current and not blocked and not native_save_wait then
     local ok2,result,why=pcall(persist,current)
     if not ok2 or not result then blocked="新周目加点继承记录未能保存："..tostring(why or result);log(blocked)
     else log("新周目继承已绑定："..current.slot) end
    end
   end)
   if ok then ng_registered[path]=true;hooked[#hooked+1]={path,a,b}end
  end
 end
end
-- Blueprint classes may load later. Discovery runs from the game-thread
-- timer below; an object-created callback must not execute on main_lua.
ensure_ng_hooks()
ensure_story_hooks()
local roster_stage_masks,roster_formic_masks={},{}
local function begin_roster_save(receiver,skip,stack)
 local mask,why=M.roster.before_formic_save(receiver,skip)
 if why then
  local restored,restore_error=M.roster.stop()
  log("临时选兵保存保护失败，已尝试撤回："..tostring(why))
  if not restored then blocked="临时选兵清理失败："..tostring(restore_error);log(blocked)end
 end
 stack[#stack+1]=mask or false
end
local function finish_roster_save(stack)
 local mask=table.remove(stack)
 if mask then
  local result,why=M.roster.after_formic_save(mask)
  if not result then log("临时选兵保存后恢复失败："..tostring(why))end
 end
end
local story_save_calls={}
safe_hook("/Script/EotU.EotUFormicariumGameMode:SaveFormicariumStage",function(receiver,suffix)
 begin_roster_save(receiver,nil,roster_stage_masks)
 local entry=false
 story_receipt=nil
 if not saving and not blocked and not completion_job and not native_save_wait and current and state
  and not (prepared_world==current.world and prepared_slot==current.slot) then
  local live=get_base_context()
  local instance=unbox(receiver)
  local name=text(unbox(suffix))
  if story_stages[name] and live and live.is_formicarium and live.world==current.world and live.slot==current.slot
   and valid(instance) and instance:GetAddress()==live.game_mode:GetAddress()
   and fingerprint(live.slot)==state.slots[live.slot].anchor then
   entry={ctx=current,state=state,suffix=name,points=clone(state.slots[live.slot].points)}
  end
 end
 story_save_calls[#story_save_calls+1]=entry
end,function()
 finish_roster_save(roster_stage_masks)
 local entry=story_save_calls[#story_save_calls];story_save_calls[#story_save_calls]=nil
 if not entry or saving or blocked or current~=entry.ctx or state~=entry.state then return end
 local fp,why=fingerprint(entry.ctx.slot,entry.suffix)
 if not fp then log("剧情阶段快照无法核验："..tostring(why));return end
 entry.stage_fp=fp
 story_receipt=entry
end)
-- A lab's BeginPlay can request its initial overlay save before the periodic
-- activation tick, including after travel while current still names the old
-- world. Validate the still-unmodified native pair at that boundary, then let
-- the existing overlay receipt observe its write. An unknown nonempty history
-- still fails activate(); no later fingerprint is adopted speculatively.
local function activate_before_formic_save(receiver)
 if saving or blocked or completion_job or native_save_wait then return end
 local live=get_base_context()
 local instance=unbox(receiver)
 if not live or not live.is_formicarium or not valid(instance)
  or instance:GetAddress()~=live.game_mode:GetAddress() then return end
 local world=instance:GetWorld()
 if not valid(world)or world:GetAddress()~=live.world then return end
 if current and current.slot==live.slot and current.world==live.world
  and activated_world==live.world then return end
 local ok,ctx=pcall(activate)
 if not ok then
  blocked="原生保存前无法核验加点记录："..tostring(ctx);log(blocked)
 end
end
local formic_save_calls={}
safe_hook("/Script/EotU.EotUFormicariumGameMode:SaveFormicarium",function(receiver,_,skip_overlay)
 activate_before_formic_save(receiver)
 begin_roster_save(receiver,skip_overlay,roster_formic_masks)
 local entry=false
 if not saving and current and not blocked then
  local live=get_base_context()
  local instance=unbox(receiver)
  if live and live.world==current.world and live.slot==current.slot and valid(instance)
   and instance:GetAddress()==live.game_mode:GetAddress() then
   local settled,settle_error=settle_native_save()
   if settled==nil then blocked="原生保存未能安全核验："..tostring(settle_error)
   elseif fingerprint(live.slot)==state.slots[live.slot].anchor then
    entry={ctx=live,anchor=state.slots[live.slot].anchor,revision=state.revision,
     skip=unbox(skip_overlay)==true,existing=save_overlays(live)}
    if not entry.skip then
     native_save_wait=native_save_wait or {world=live.world,slot=live.slot,mode=instance:GetAddress(),
      anchor=entry.anchor,revision=entry.revision,overlays={}}
     native_save_wait.collecting=true
    end
   end
  end
 end
 formic_save_calls[#formic_save_calls+1]=entry
end,function()
 finish_roster_save(roster_formic_masks)
 local entry=formic_save_calls[#formic_save_calls];formic_save_calls[#formic_save_calls]=nil
 if not entry or saving or blocked then return end
 local live=get_base_context()
 if not live or live.world~=entry.ctx.world or live.slot~=entry.ctx.slot then return end
 if entry.skip then
  if not native_save_wait then
   local ok,fp,why=pcall(persist,live)
   if not ok or not fp then blocked="保存同步失败："..tostring(why or fp);log(blocked)end
  end
 else
  local added=0
  for address,overlay in pairs(save_overlays(live))do
   if not entry.existing[address] and tonumber(overlay.TickCounter)==0 then
    native_save_wait.overlays[address]=true;added=added+1
   end
  end
  native_save_wait.collecting=false
  if added~=1 then blocked="无法确认本次原生保存提示，已停止后续加点";log(blocked) end
 end
end)
-- Mission rewards and level saves can write the compressed native files from
-- C++, bypassing both SaveFormicarium and the GameplayStatics Blueprint hook.
-- Bind only a save observed from a matching, already-active live context.
local function observe_native_save(path,kind,skip_observer)
 local observed={}
 safe_hook(path,function(receiver,object,slot,...)
  -- Pair every callback, including skipped previews, without losing an outer
  -- real save if a native operation invokes another reward calculation.
  observed[#observed+1]=false
  if saving or blocked or native_save_wait or not current or not state then return end
  local live=get_base_context()
  if not live or live.world~=current.world or live.slot~=current.slot then return end
  if kind=="compressed" then
   local name=text(unbox(slot))
   if name~=current.slot and name~=current.slot.."LevelData" then return end
   if not valid(unbox(object)) then return end
  else
   local instance=unbox(receiver)
   local expected=kind=="state" and current.game_state or current.game_mode
   if not valid(instance) or instance:GetAddress()~=expected:GetAddress() then return end
  end
  if skip_observer and skip_observer(current,receiver,object,slot,...) then return end
  local fp=fingerprint(current.slot)
  if fp~=state.slots[current.slot].anchor then return end
  observed[#observed]={ctx=current,fp=fp}
 end,function()
  local entry=observed[#observed];observed[#observed]=nil
  if not entry or saving or blocked or native_save_wait or current~=entry.ctx then return end
  local live=get_base_context()
  if not live or live.world~=entry.ctx.world or live.slot~=entry.ctx.slot then return end
  local after=fingerprint(entry.ctx.slot)
  if not after or after==entry.fp then return end
  local ok,fp,why=pcall(persist,entry.ctx)
  if not ok or not fp then blocked="原生保存同步失败："..tostring(why or fp);log(blocked) end
 end)
end
local function reward_bool(value)
 if type(value)=="boolean" then return value end
 local ok,result=pcall(function()return value:get()end)
 if ok and type(result)=="boolean" then return result end
end
local function native_reward_preview(ctx,receiver,level,territory,jelly,resources,defeat,
 override_difficulty,override_challenge,difficulty,challenge,force_completed,preloaded)
 -- The story menu calculates normal/challenge reward previews from its loaded
 -- profile. Neither calculation saves or grants rewards. Do not hash both save
 -- files four times for every level/difficulty click. Unknown calls still take
 -- the full observer path; actual save hooks remain independently active.
 return ctx.is_formicarium==true and valid(unbox(preloaded))
  and reward_bool(territory)==false and reward_bool(jelly)==false
  and reward_bool(resources)==false and reward_bool(defeat)==false
  and reward_bool(override_difficulty)==true and reward_bool(override_challenge)==true
end
observe_native_save("/Script/EotU.EotUGameState:CalculateRewards","state",native_reward_preview)
-- Mission completion calls the native CalculateRewards and SaveGameToSlot
-- implementations directly inside this function. Their UFunction hooks do
-- not see that final primary-save write; observe the complete operation.
observe_native_save("/Script/EotU.EotUGameState:SetupReturnToFormicarium","state")
observe_native_save("/Script/EotU.EotUGameState:AddDefeatResourceToRewardsPool","state")
observe_native_save("/Script/EotU.EotUGameMode:SaveLevel","mode")
observe_native_save("/Script/EotU.EotUSaveGameUtilities:SaveGameCompressed","compressed")
safe_hook("/Script/Engine.GameplayStatics:SaveGameToSlot",function()end,function(_,result,object,slot)
 if saving or blocked or native_save_wait or not current or unbox(result)~=true then return end
 local slot_name=text(unbox(slot))
 if slot_name~=current.slot and slot_name~=current.slot.."LevelData" then return end
 local live=get_base_context()
 if not live or live.world~=current.world or live.slot~=current.slot then return end
 local ok,fp,why=pcall(persist,current)
 if not ok or not fp then blocked="原生存档与扩展记录同步失败："..tostring(why or fp);log(blocked)end
end)
safe_hook("/Script/EotU.EotUFormicariumGameMode:LoadFormicarium",function()
 if M.ui and M.ui.invalidate then M.ui.invalidate("native_campaign_load") end
 current,activated_world=nil,nil
 native_save_wait=nil
 extra.reset_cache()
 if M.skills then M.skills.invalidate()end
 if M.skills_runtime then M.skills_runtime.reset_cache()end
 if M.reset_slaver_cache then local ok,why=M.reset_slaver_cache();if not ok then log(why)end end
 skill_births={};skill_scan_requested=true
 activation_requested=true
end,function()
 activation_requested=true
end)
safe_hook("/Script/EotU.EotUGameMode:ApplyColonySetup",function()end,function()
 activation_requested=true
end)
local refresh_health={}
safe_hook("/Script/EotU.EotUGameState:RefreshAllTennentsOfTileType",function()
 refresh_health={}
 if not current or not state or not state.slots[current.slot] then return end
 local expanded=groups.expand(state.slots[current.slot].points) or {}
 for _,c in ipairs(FindAllOf("Creature") or {}) do
  if valid(c) and expanded[groups.canonical_name(text(c.CreatureName))] and native.is_owned(c,current.game_state) then
   refresh_health[#refresh_health+1]={creature=c,health=c.Health}
  end
 end
end,function()
 for _,entry in ipairs(refresh_health) do
  if valid(entry.creature) then
   if M.slaver_balance then
    M.slaver_balance.note_rebuild(entry.creature)
    local balanced,why=M.slaver_balance.apply(entry.creature);if not balanced then log(why)end
   end
   entry.creature.Health=math.min(entry.health,entry.creature.FullHealth)
  end
 end
 refresh_health={}
end)

-- Native colony buffs are read by newly hatched ants. Poll only binds a new
-- campaign/world, or restores our named buff entries if stock code rebuilt them.
local runtime_started=false
local function refresh_skill_creature(creature)
 if not current or not valid(creature) or creature.Health<=0
  or text(creature.CreatureName):lower()~='trapjawant' or not native.is_owned(creature,current.game_state)then return end
 local allocations=state and state.slots[current.slot] and state.slots[current.slot].points
 local expanded=allocations and groups.expand(allocations)or{}
 local result,why=apply_extra(creature,expanded[groups.canonical_name(text(creature.CreatureName))]or{})
 if not result then log('技能刷新：'..tostring(why))end
end
M.refresh_custom_skills=function()
 if not current then return end
 for _,creature in ipairs(FindAllOf('TrapjawAnt_C')or{})do refresh_skill_creature(creature)end
 skill_scan_requested=false
end
local function queue_skill_creature(creature,rebuilt)
 creature=unbox(creature)
 if valid(creature)and M.slaver_runtime then
  if rebuilt then M.slaver_runtime.forget(creature)end
  slaver_births[tostring(creature:GetAddress())]=creature
  if rebuilt and M.slaver_conversion.has_snapshot(creature)==true then
   slaver_rebuilds[tostring(creature:GetAddress())]=creature
  end
 end
 if valid(creature)and M.slaver_conversion and M.slaver_conversion.has_snapshot(creature)==true then return end
 if valid(creature) and text(creature.CreatureName):lower()=='trapjawant'then
  if rebuilt then
   extra.forget(creature)
   if M.skills_runtime then M.skills_runtime.forget(creature)end
  end
  skill_births[tostring(creature:GetAddress())]=creature
 end
end
local pending_skill_rebuilds={}
local function defer_skill_rebuild(c)
 c=unbox(c)
 local ok,address=pcall(function()return c:GetAddress()end)
 if not ok or not address then return end
 local key=tostring(address)
 if pending_skill_rebuilds[key]then return end
 pending_skill_rebuilds[key]=c
 ExecuteInGameThreadAfterFrames(2,function()
  local creature=pending_skill_rebuilds[key];pending_skill_rebuilds[key]=nil
  if creature then queue_skill_creature(creature,true)end
 end)
end
-- These native calls also run while deferred-spawn objects are incomplete.
-- Only enqueue the wrapper here; reflection waits until initialization ends.
safe_hook('/Script/EotU.Creature:LookupApplyAbilitiesForLevel',function()end,defer_skill_rebuild)
local function defer_stat_rebuild(c)
 if M.slaver_balance then M.slaver_balance.note_rebuild(c)end
 defer_skill_rebuild(c)
end
safe_hook('/Script/EotU.Creature:LookupApplyStatsForLevel',function()end,defer_stat_rebuild)
safe_hook('/Script/EotU.Creature:ChangeCreatureLevel',function()end,defer_stat_rebuild)
if type(NotifyOnNewObject)=='function'then
 NotifyOnNewObject('/Game/Blueprints/Creatures/OtherColonyCreatures/TrapjawAnt.TrapjawAnt_C',function(creature)
  ExecuteInGameThreadAfterFrames(2,function()queue_skill_creature(creature)end)
 end)
end
function M.start_runtime()
 if runtime_started then return end
 runtime_started=true
 -- Test instrumentation is inserted inside this game-thread bootstrap only.
 -- DIAGNOSTIC_BOOTSTRAP_POINT
 M.ui.start_input()
 assert(type(LoopInGameThreadAfterFrames)=="function","This build requires the verified UE4SS EngineTick timer")
 LoopInGameThreadAfterFrames(5,function()
  if completion_job then return end
  local ok,err=pcall(M.roster.tick)
  if not ok then log("选兵功能："..tostring(err))end
   if M.skills_purchase then M.skills_purchase.tick()end
   local slaver_ok,slaver_error=pcall(M.tick_slaver)
   if not slaver_ok then log('俘虏功能：'..tostring(slaver_error))end
   if current and not completion_job and not native_save_wait then
    if skill_scan_requested then M.refresh_custom_skills()end
    local births=skill_births;skill_births={}
    for _,creature in pairs(births)do refresh_skill_creature(creature)end
   end
 end)
 LoopInGameThreadAfterFrames(30,function()
  if completion_job then return end
  local ok,err=pcall(function()
    if M.ui and M.ui.validate then M.ui.validate() end
    ensure_ng_hooks()
    ensure_story_hooks()
    tick_context()
    M.foreign_ui.tick()
     if M.skills_runtime then M.skills_runtime.tick()end
    if current then sync(current,false) end
  end)
  if not ok then log(err) end
 end)
end
log("已加载。原小幅改进面板内按 F6 打开扩展属性，F7 返回。")
-- This must be the last top-level registration: once hook_lua can run, no
-- further main_lua callback may push functions onto its shared Lua stack.
ExecuteInGameThreadAfterFrames(1,function() M.start_runtime() end)
return M
