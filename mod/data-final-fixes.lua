-- Native consume-only recipes provide real progress, energy use, animations
-- and Alt recipe display. Completed crafts are settled by runtime into the
-- independent byproduct inventory, avoiding native result-slot filters.
local recipes={}
local function placed_prototype(kind,name)
  for type_name in pairs(defines.prototypes[kind]) do
    if data.raw[type_name] and data.raw[type_name][name] then return data.raw[type_name][name] end
  end
end
local function item_name(item)
  if item.localised_name then return item.localised_name end
  if item.place_result then
    local entity=placed_prototype("entity",item.place_result)
    return entity and entity.localised_name or {"entity-name."..item.place_result}
  elseif item.place_as_equipment_result then
    local equipment=placed_prototype("equipment",item.place_as_equipment_result)
    return equipment and equipment.localised_name or {"equipment-name."..item.place_as_equipment_result}
  elseif item.place_as_tile then
    local tile=data.raw.tile[item.place_as_tile.result]
    if tile and tile.localised_name then return tile.localised_name end
  end
  return {"item-name."..item.name}
end
-- Discover every physical item subtype, including ammo, armor, guns, repair
-- tools, science packs and vehicles. Selection/planning tools are UI data,
-- not production items. Non-stackable equipment is deliberately supported.
local planning_tools={
  ["blueprint"]=true,["blueprint-book"]=true,["copy-paste-tool"]=true,
  ["deconstruction-item"]=true,["upgrade-item"]=true,["selection-tool"]=true,
  ["spidertron-remote"]=true
}
for kind in pairs(defines.prototypes.item) do
  for name,item in pairs(data.raw[kind] or {}) do
    local perishable=(item.spoil_ticks or 0)>0
    local eligible=not item.hidden and not planning_tools[kind] and not name:find("^parameter%-%d+$")
    for _,flag in pairs(item.flags or {}) do if flag=="only-in-cursor" then eligible=false end end
    if eligible then
      recipes[#recipes+1]={type="recipe",name="quality-upcycling-"..name,localised_name={"recipe-name.quality-upcycling",item_name(item)},
        icon=item.icon,icons=table.deepcopy(item.icons),icon_size=item.icon_size,
        categories={"quality-upcycling"},hidden=true,enabled=true,hide_from_player_crafting=true,allow_decomposition=false,preserve_products_in_machine_output=true,
        allow_quality=true,allow_productivity=false,auto_recycle=false,raise_on_crafted=true,
        energy_required=(data.raw.recipe[name.."-recycling"] or {}).energy_required or math.max((data.raw.recipe[name] or {}).energy_required or 0.5,0.0176)/16,
        ingredients={{type="item",name=name,amount=1}},
        -- The temporary native result only keeps the original age alive.
        -- Runtime records the actual surviving product and its final quality.
        results=perishable and {{type="item",name=name,amount=1,ignored_by_stats=1,affected_by_quality=false,always_fresh=false,reset_freshness_on_craft=false}} or {}}
    end
  end
end
data:extend(recipes)
