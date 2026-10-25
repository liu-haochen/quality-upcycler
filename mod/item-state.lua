-- Native crafting consumes an ingredient before its completion event. Keep a
-- one-item copy for items carrying data so surviving outputs retain that data.
-- These copies are bookkeeping, never additional refundable input items.
local M={}
local function copy_inventory(source,target)
  if not source or not target then return end
  for i=1,#source do
    if source[i].valid_for_read then
      assert(i<=#target and target[i].set_stack(source[i]),"Upcycler could not preserve item inventory")
    end
    if source.supports_filters() and target.supports_filters() and i<=#target then
      target.set_filter(i,source.get_filter(i))
    end
  end
  if source.supports_bar() and target.supports_bar() then target.set_bar(source.get_bar()) end
end
local function copy_grid(source,target)
  if not source then return end
  assert(target,"Upcycler output has no equipment grid")
  for _,equipment in pairs(source.equipment) do
    local ghost=equipment.type=="equipment-ghost"
    local added=target.put{name=ghost and equipment.ghost_name or equipment.name,
      quality=equipment.quality,position=equipment.position,ghost=ghost}
    assert(added,"Upcycler could not preserve installed equipment")
    if not ghost then
      added.energy=equipment.energy
      if equipment.type=="energy-shield-equipment" then added.shield=equipment.shield end
      if equipment.burner and added.burner then
        copy_inventory(equipment.burner.inventory,added.burner.inventory)
        copy_inventory(equipment.burner.burnt_result_inventory,added.burner.burnt_result_inventory)
        added.burner.currently_burning=equipment.burner.currently_burning
        added.burner.remaining_burning_fuel=equipment.burner.remaining_burning_fuel
        added.burner.heat=equipment.burner.heat
      end
    end
  end
end
function M.clear(s)
  if s.item_snapshot and s.item_snapshot.valid then s.item_snapshot.destroy() end
  s.item_snapshot=nil;s.item_condition=nil;s.durability_ratio=nil
end
function M.capture(s,stack,info,quality)
  M.clear(s)
  if info then
    -- prepare() already validated the slot. Most materials carry only health;
    -- complete magazines and tools have no condition that needs restoring.
    if info.perishable then return end
    if info.plain then
      local health=stack.health
      if health~=1 then s.item_condition={name=info.name,quality=quality,count=1,health=health} end
      return
    end
    if info.kind=="ammo" or info.kind=="tool" or info.kind=="repair-tool" then
      local health=stack.health
      local changed=health~=1
      local ammo,durability
      if info.kind=="ammo" then
        ammo=stack.ammo
        if not info.magazine_size then info.magazine_size=info.prototype.magazine_size end
        changed=changed or ammo~=info.magazine_size
      elseif info.kind=="tool" or info.kind=="repair-tool" then
        local maximum=info.durability[quality]
        if not maximum then maximum=info.prototype.get_durability(quality);info.durability[quality]=maximum end
        if maximum and maximum>0 then
          durability=stack.durability
          changed=changed or durability~=maximum
          if changed then s.durability_ratio=durability/maximum end
        end
      end
      if changed then s.item_condition={name=info.name,quality=quality,count=1,health=health,ammo=ammo,durability=durability} end
      return
    end
  else
    if not stack.valid_for_read then return end
    -- Spoilable products use a real staging stack and existing age tracking.
    if stack.prototype.get_spoil_ticks(stack.quality)>0 then return end
    if not stack.item and not stack.is_ammo and not stack.is_tool
      and not stack.is_armor and not stack.is_repair_tool and stack.health==1 then return end
  end
  s.item_snapshot=game.create_inventory(1)
  assert(s.item_snapshot[1].set_stack(stack))
  s.item_snapshot[1].count=1
end
function M.result(s,name,quality,result_quality)
  local condition=s.item_condition;s.item_condition=nil
  local ratio=s.durability_ratio;s.durability_ratio=nil
  if condition then
    if not result_quality or condition.name~=name or condition.quality~=quality then return nil end
    condition.quality=result_quality
    if ratio then condition.durability=ratio*prototypes.item[name].get_durability(result_quality) end
    return condition
  end
  local snapshot=s.item_snapshot;s.item_snapshot=nil
  if not snapshot then return nil end
  local source=snapshot[1]
  if not source.valid_for_read or source.name~=name or source.quality.name~=quality or not result_quality then
    snapshot.destroy();return nil
  end
  if result_quality==quality then return {stack=snapshot} end
  local output=game.create_inventory(1)
  local definition={name=name,quality=result_quality,count=1,health=source.health}
  if source.is_ammo then definition.ammo=source.ammo end
  if source.is_tool or source.is_armor or source.is_repair_tool then
    local maximum=source.prototype.get_durability(quality)
    if maximum and maximum>0 then
      definition.durability=source.durability/maximum*source.prototype.get_durability(result_quality)
    end
  end
  if source.is_item_with_tags then definition.tags=source.tags;definition.custom_description=source.custom_description end
  assert(output[1].set_stack(definition))
  local target=output[1]
  if source.is_item_with_label then
    if source.label then target.label=source.label end
    if source.label_color then target.label_color=source.label_color end
    target.allow_manual_label_change=source.allow_manual_label_change
  end
  if source.is_item_with_entity_data then
    for _,key in ipairs({"entity_label","entity_color","entity_logistic_sections","entity_request_from_buffers",
      "entity_logistics_enabled","entity_enable_logistics_while_moving","entity_driver_is_gunner",
      "entity_auto_target_without_gunner","entity_auto_target_with_gunner"}) do
      if source[key]~=nil then target[key]=source[key] end
    end
  end
  copy_inventory(source.get_inventory(defines.inventory.item_main),target.get_inventory(defines.inventory.item_main))
  if source.grid then copy_grid(source.grid,target.grid or target.create_grid()) end
  snapshot.destroy()
  return {stack=output}
end
function M.refund(s,buffer)
  local snapshot=s.item_snapshot
  if not snapshot and s.item_condition then
    snapshot=game.create_inventory(1)
    assert(snapshot[1].set_stack(s.item_condition))
    s.item_condition=nil;s.durability_ratio=nil
  end
  if not snapshot then return nil end
  local stack=snapshot[1]
  if buffer then
    -- Input/output inventories may also contain this item. Only replace a
    -- pristine, empty native refund, never a different data-bearing item.
    for i=1,#buffer do
      local candidate=buffer[i]
      if candidate.valid_for_read and candidate.name==stack.name and candidate.quality==stack.quality and candidate.health==1 then
        local grid=candidate.grid
        local inner=candidate.get_inventory(defines.inventory.item_main)
        local plain=(not grid or #grid.equipment==0) and (not inner or inner.is_empty())
        if candidate.is_ammo then plain=plain and candidate.ammo==candidate.prototype.magazine_size end
        if candidate.is_tool or candidate.is_armor or candidate.is_repair_tool then
          local maximum=candidate.prototype.get_durability(candidate.quality)
          plain=plain and (not maximum or candidate.durability==maximum)
        end
        if candidate.is_item_with_tags then plain=plain and next(candidate.tags)==nil end
        if candidate.is_item_with_label then plain=plain and (not candidate.label or candidate.label=="") end
        if candidate.is_item_with_entity_data then plain=plain and not candidate.entity_label and not candidate.entity_color end
        if plain then candidate.count=candidate.count-1;break end
      end
    end
  end
  s.item_snapshot=nil
  return {stack=snapshot}
end
return M
