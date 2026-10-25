local kernel=require("kernel")
local item_state=require("item-state")
local NAME="quality-upcycler"
local PREFIX="quality-upcycling-"
local VERSION=6
-- Volatile caches are rebuilt after loading; inventories and waiting queues
-- live in storage so partially completed jobs survive save/load unchanged.
local quality_cache={}
local item_cache={}
local flow_cache={}
-- These parameter tables are consumed synchronously by native inventory/stat
-- APIs. Share them across callbacks instead of retaining three per machine.
local product_definition={count=1}
local function push_pending(s,item)
  local t=s.pending;t[#t+1]=item
end
local function push_spoil(s,item)
  local t=s.spoil_pending;t[#t+1]=item
end
local flow_definition={}
local recipe_cache={}
local function production_flow(force_index,surface_index)
  local by_surface=flow_cache[force_index]
  if not by_surface then by_surface={};flow_cache[force_index]=by_surface end
  local entry=by_surface[surface_index]
  if not entry or not entry.object.valid then
    local object=game.forces[force_index].get_item_production_statistics(surface_index)
    entry={object=object,add=object.on_flow};by_surface[surface_index]=entry
  end
  return entry.add
end
local function item_info(name)
  local info=item_cache[name]
  if not info then
    local prototype=prototypes.item[name]
    local kind=prototype.type
    info={name=name,prototype=prototype,kind=kind,perishable=prototype.get_spoil_ticks("normal")>0,spoil_ticks={},durability={},
      plain=kind=="item" or kind=="module" or kind=="capsule" or kind=="gun" or kind=="rail-planner" or kind=="space-platform-starter-pack"}
    item_cache[name]=info
  end
  return info
end


local function build_recipe_cache()
  recipe_cache={}
  for recipe_name,recipe in pairs(prototypes.recipe) do
    if recipe_name:sub(1,#PREFIX)==PREFIX then
      local item_name=recipe_name:sub(#PREFIX+1)
      local info=item_info(item_name)
      recipe_cache[recipe_name]={name=item_name,info=info,perishable=info.perishable}
    end
  end
end
build_recipe_cache()


local function spoil_ticks(name,quality)
  local info=item_info(name)
  local ticks=info.spoil_ticks[quality]
  if not ticks then ticks=info.prototype.get_spoil_ticks(quality);info.spoil_ticks[quality]=ticks end
  return ticks
end
local function qualities(key)
  local info=quality_cache[key]
  if not info then
    local force=game.forces[key]
    local names={"normal"};local ranks={normal=1};local q=prototypes.quality.normal.next
    while q and force.is_quality_unlocked(q.name) do
      names[#names+1]=q.name;ranks[q.name]=#names;q=q.next
    end
    info={names=names,ranks=ranks};quality_cache[key]=info
  end
  return info
end
local function status(s,key,color)
  local cache=key or false
  if s.status_key==cache then return end
  s.status_key=cache
  if key then s.entity.custom_status={diode=defines.entity_status_diode[color],label={"quality-upcycler.status-"..key}}
  else s.entity.custom_status=nil end
end
local function enabled(s,value)
  local disabled=not value
  if s.disabled~=disabled then s.entity.disabled_by_script=disabled;s.disabled=disabled end
end
local function wait(s,mode)
  enabled(s,false);s.wait=mode;storage.waiting[s.unit]=s
  status(s,mode=="blocked" and "full" or "waiting","yellow")
end
local function module_quality(e)
  local q=0;local inv=e.get_module_inventory()
  if inv then for _,item in pairs(inv.get_contents()) do
    q=q+(prototypes.item[item.name].get_module_effects(item.quality).quality or 0)*item.count
  end end
  return math.max(0,math.min(1,q))
end
local function current(e)
  local recipe,quality=e.get_recipe()
  if not recipe or recipe.name:sub(1,#PREFIX)~=PREFIX then return nil end
  return {name=recipe.name:sub(#PREFIX+1),quality=quality.name}
end
local function cleanup(s)
  item_state.clear(s)
  for _,item in ipairs(s.pending or {}) do if item.stack and item.stack.valid then item.stack.destroy() end end
  storage.waiting[s.unit]=nil;storage.machines[s.unit]=nil
  if s.registration then storage.registrations[s.registration]=nil end
end
local function main_stack(s,item)
  local staging=s.entity.get_output_inventory()
  for i=1,#staging do
    local stack=staging[i]
    if stack.valid_for_read and stack.name==item.name and stack.quality.name==item.source_quality then return stack end
  end
end
local function flush(s)
  while #s.spoil_pending>0 do
    local item=s.spoil_pending[1]
    local stack=main_stack(s,item)
    if stack then
      -- ItemStackDefinition carries freshness directly; no temporary inventory
      -- or second transfer is needed to create a single aged output item.
      if s.output.insert{name=item.name,quality=item.quality,count=1,spoil_percent=stack.spoil_percent}==0 then return false end
      stack.count=stack.count-1
    end
    table.remove(s.spoil_pending,1)
  end
  if s.check_staging then
    local staging=s.entity.get_output_inventory()
    if not staging.is_empty() then s.output.transfer_from_inventory(staging) end
    if not staging.is_empty() then return false end
    s.check_staging=false
  end
  while #s.pending>0 do
    local item=s.pending[1]
    if item.stack then
      s.output.transfer_from_stack(item.stack[1])
      if item.stack[1].valid_for_read then return false end
      item.stack.destroy()
    elseif s.output.insert(item)==0 then return false end
    table.remove(s.pending,1)
  end
  return true
end
local function prepare(s,chain)
  if (#s.pending>0 or #s.spoil_pending>0 or s.check_staging) and not flush(s) then wait(s,"blocked");return end
  if s.resume then
    s.resume=nil;enabled(s,true);s.wait=nil;storage.waiting[s.unit]=nil;status(s,nil);return
  end
  local stack=s.slot
  if s.refund and s.input.insert(s.refund)==1 then s.refund=nil end
  if not stack.valid_for_read then
    item_state.clear(s);s.craft_freshness=nil;wait(s,"waiting");return
  end
  local name=stack.name;local quality=stack.quality.name
  chain=chain or qualities(s.entity.force_index)
  if s.output.is_full() then wait(s,"blocked");return end
  local info=item_info(name)
  local needs_handoff
  if info.perishable then
    if s.item_snapshot or s.item_condition then item_state.clear(s) end
    s.craft_freshness={name=name,quality=quality,percent=stack.spoil_percent,tick=game.tick}
    needs_handoff=true
  else
    s.craft_freshness=nil
    if not info.plain or stack.health~=1 then
      item_state.capture(s,stack,info,quality)
      needs_handoff=true
    else
      if s.item_snapshot or s.item_condition then item_state.clear(s) end
      -- Plain, pristine items carry no state that can change during the
      -- engine handoff. Enable the machine and let the native engine start;
      -- only complex/perishable items need the extra one-tick observation.
      needs_handoff=false
    end
  end
  enabled(s,true)
  if needs_handoff then
    s.wait="starting";storage.waiting[s.unit]=s
  else
    s.wait=nil;storage.waiting[s.unit]=nil
  end
  status(s,chain.ranks[quality]==#chain.names and "capped" or nil,"yellow")
end
local function register(e)
  if not e or not e.valid or e.name~=NAME then return end
  storage.machines=storage.machines or {};storage.waiting=storage.waiting or {};storage.registrations=storage.registrations or {}
  storage.rng=storage.rng or game.create_random_generator()
  local unit=e.unit_number
  local s=storage.machines[unit] or {entity=e,processed=0,destroyed=0,kept=0,upgraded=0,passed=0}
  if s.stats then
    s.processed=s.processed or s.stats.processed or 0
    s.destroyed=s.destroyed or s.stats.destroyed or 0
    s.kept=s.kept or s.stats.kept or 0
    s.upgraded=s.upgraded or s.stats.upgraded or 0
    s.passed=s.passed or s.stats.passed or 0
    s.spoiled=s.spoiled or s.stats.spoiled
    s.stats=nil
  end
  s.processed=s.processed or 0;s.destroyed=s.destroyed or 0;s.kept=s.kept or 0
  s.upgraded=s.upgraded or 0;s.passed=s.passed or 0
  if s.native_version~=3 then
    s.pending=s.pending or {}
    if s.job then
      if s.job.result then push_pending(s,{name=s.job.name,quality=s.job.result,count=1})
      else s.refund={name=s.job.name,quality=s.job.quality,count=1} end
      s.job=nil
    end
    for _,key in ipairs({"icon","badge"}) do if s[key] and s[key].valid then s[key].destroy() end;s[key]=nil end
    s.native_version=3
  end
  s.entity=e;s.unit=unit;s.pending=s.pending or {};s.spoil_pending=s.spoil_pending or {}
  s.input=e.get_inventory(defines.inventory.crafter_input);s.slot=s.input[1]
  s.output=e.get_inventory(defines.inventory.crafter_trash)
  s.query=nil;s.product=nil;s.flow=nil
  s.statistics=nil;s.statistics_force=nil;s.statistics_surface=nil
  -- Reconcile once on first update too: other on_init handlers can populate
  -- a legacy result inventory immediately after the build event registered us.
  s.check_staging=true
  s.disabled=e.disabled_by_script;s.status_key=nil;s.mining_snapshot=nil
  s.registration=script.register_on_object_destroyed(e)
  storage.registrations[s.registration]=unit;storage.machines[unit]=s
  if e.is_crafting() then
    if #s.pending>0 or #s.spoil_pending>0 or s.check_staging then s.resume=true;wait(s,"blocked")
    else s.resume=nil;s.wait=nil;storage.waiting[unit]=nil;enabled(s,true);status(s,nil) end
  else s.resume=nil;wait(s,"waiting") end
end
local function scan()
  storage.machines=storage.machines or {};storage.waiting={};storage.registrations={}
  storage.rng=storage.rng or game.create_random_generator();quality_cache={};item_cache={};flow_cache={}
  for unit,s in pairs(storage.machines) do if not s.entity.valid then s.unit=unit;cleanup(s) end end
  for _,force in pairs(game.forces) do
    local technology=force.technologies["quality-module"]
    if technology and technology.researched then force.recipes[NAME].enabled=true end
  end
  storage.unlock_version=1
  for _,surface in pairs(game.surfaces) do
    for _,e in pairs(surface.find_entities_filtered{name=NAME}) do register(e) end
  end
  storage.runtime_version=VERSION
end
script.on_init(scan)
script.on_configuration_changed(scan)
local function built(event) register(event.entity or event.created_entity or event.destination) end
for _,event in ipairs({defines.events.on_built_entity,defines.events.on_robot_built_entity,defines.events.script_raised_built,
  defines.events.script_raised_revive,defines.events.on_entity_cloned,defines.events.on_space_platform_built_entity}) do script.on_event(event,built) end
local function crafted(event)
  local e=event.entity
  if not e.valid or e.name~=NAME then return end
  local s=storage.machines[e.unit_number]
  if not s then register(e);s=storage.machines[e.unit_number] end
  local recipe=recipe_cache[event.recipe]
  local name=recipe and recipe.name or event.recipe:sub(#PREFIX+1)
  local quality=event.recipe_quality
  local info=recipe and recipe.info or item_info(name)
  local perishable=recipe and recipe.perishable or info.perishable
  local original=perishable and main_stack(s,{name=name,source_quality=quality}) or nil
  if original then
    local age=s.craft_freshness or s.input_freshness
    if age and age.name==name and age.quality==quality then
      original.spoil_percent=math.min(1,age.percent+(game.tick-age.tick)/spoil_ticks(name,quality))
      if not original.valid_for_read or original.name~=name then original=nil end
    end
  end
  s.craft_freshness=nil;s.input_freshness=nil
  if perishable then s.check_staging=true end
  if perishable and not original then
    s.spoiled=(s.spoiled or 0)+1;prepare(s);return
  end
  local force_index=e.force_index
  local chain=qualities(force_index);local rank=chain.ranks[quality];local result
  if not rank or rank==#chain.names then result=quality;s.passed=s.passed+1
  else
    local q=event.quality_effect or module_quality(e)
    local chosen=kernel.choose(kernel.profile(q,#chain.names),rank,storage.rng())
    s.processed=s.processed+1
    if not chosen then s.destroyed=s.destroyed+1
    else
      result=chain.names[chosen]
      if result==quality then s.kept=s.kept+1 else s.upgraded=s.upgraded+1 end
    end
  end
  if perishable then
    if not result then original.count=original.count-1
    else push_spoil(s,{name=name,source_quality=quality,quality=result}) end
  else
    local preserved
    if s.item_condition or s.item_snapshot then
      preserved=item_state.result(s,name,quality,result)
    end
    if result then
      if preserved then push_pending(s,preserved)
      else
        local product=product_definition;product.name=name;product.quality=result
        if s.output.insert(product)==0 then push_pending(s,{name=name,quality=result,count=1}) end
      end
    end
  end
  if result then
    local flow=flow_definition;flow.name=name;flow.quality=result
    production_flow(force_index,e.surface_index)(flow,1)
  end
  prepare(s,chain)
end
for name,recipe in pairs(prototypes.recipe) do
  if name:sub(1,#PREFIX)==PREFIX and recipe.on_crafted_event then script.on_event(recipe.on_crafted_event,crafted) end
end
script.on_event(defines.events.on_tick,function()
  if storage.runtime_version~=VERSION or storage.unlock_version~=1 then scan() end
  for _,s in pairs(storage.waiting) do
    if not s.entity.valid then cleanup(s)
    elseif s.wait=="starting" then
      if s.entity.is_crafting() then s.wait=nil;storage.waiting[s.unit]=nil
      else prepare(s) end
    elseif s.wait=="blocked" then
      -- A full inventory cannot accept any quality. This single native check
      -- replaces repeated Lua queries for every possible output quality.
      if not s.output.is_full() then prepare(s) end
    elseif s.slot.valid_for_read or s.refund then prepare(s) end
  end
end)
script.on_event(defines.events.on_object_destroyed,function(event)
  local unit=storage.registrations and storage.registrations[event.registration_number]
  local s=unit and storage.machines[unit]
  if s then cleanup(s) end
end)
local function invalidate_quality() quality_cache={} end
script.on_event(defines.events.on_research_finished,invalidate_quality)
script.on_event(defines.events.on_research_reversed,invalidate_quality)
script.on_event(defines.events.on_forces_merged,function() invalidate_quality();flow_cache={} end)
script.on_event(defines.events.on_surface_deleted,function() flow_cache={} end)
-- Covers direct force.unlock_quality() calls by other mods without polling
-- every force or every machine on each game tick.
script.on_nth_tick(60,invalidate_quality)
local function before_mined(event)
  local e=event.entity
  local s=e and e.valid and e.name==NAME and storage.machines and storage.machines[e.unit_number]
  if s then s.mining_snapshot=e.crafting_progress>0 and (s.item_snapshot or s.item_condition) or nil end
end
script.on_event(defines.events.on_pre_player_mined_item,before_mined)
script.on_event(defines.events.on_robot_pre_mined,before_mined)
script.on_event(defines.events.on_space_platform_pre_mined,before_mined)
local function mined(event)
  local e=event.entity
  if not e or not e.valid or e.name~=NAME then return end
  local s=storage.machines and storage.machines[e.unit_number]
  if s then
    if s.mining_snapshot then
      local refund=item_state.refund(s,event.buffer)
      if refund then push_pending(s,refund) end
      s.mining_snapshot=nil
    end
    if s.refund then push_pending(s,s.refund) end
    for _,item in ipairs(s.pending) do
      local stack=item.stack and item.stack[1] or item
      if not event.buffer or event.buffer.insert(stack)==0 then e.surface.spill_item_stack{position=e.position,stack=stack,enable_looted=true,force=e.force} end
      if item.stack then item.stack.destroy() end
    end
    s.pending={};cleanup(s)
  end
end
script.on_event(defines.events.on_player_mined_entity,mined)
script.on_event(defines.events.on_robot_mined_entity,mined)
script.on_event(defines.events.on_space_platform_mined_entity,mined)
commands.add_command("quality-upcycler-give",{"quality-upcycler.command-help"},function(command)
  local player=command.player_index and game.get_player(command.player_index)
  if not player then return end
  if game.is_multiplayer() and not player.admin then player.print({"quality-upcycler.admin-only"});return end
  local count=math.max(1,math.min(100,math.floor(tonumber(command.parameter) or 5)))
  player.print({"quality-upcycler.given",player.insert{name=NAME,count=count}})
end)
remote.add_interface(NAME,{get_state=function(unit)
  local s=storage.machines and storage.machines[unit]
  if not s or not s.entity.valid then return end
  local e=s.entity;local r,q=e.get_recipe();local a=current(e);local rate=module_quality(e)
  local stats={processed=s.processed,destroyed=s.destroyed,kept=s.kept,upgraded=s.upgraded,passed=s.passed}
  if s.spoiled then stats.spoiled=s.spoiled end
  return {stats=stats,job=e.is_crafting() and a and {name=a.name,quality=a.quality,q=rate,progress=e.crafting_progress} or nil,
    pending=s.pending,spoil_pending=s.spoil_pending,quality_rate=rate,progress=e.crafting_progress,crafting_speed=e.crafting_speed,
    current_recipe=r and r.name,alt_item=a and a.name,alt_quality=q and q.name,waiting=s.wait}
end})


