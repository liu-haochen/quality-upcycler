-- Benchmark-only changes eliminate refilling/draining Lua loops and logistics
-- entities. No production mod files are changed or installed by this harness.
for kind in pairs(defines.prototypes.item) do
  for _,name in ipairs({"iron-gear-wheel","iron-plate","copper-plate","processing-unit","firearm-magazine","automation-science-pack","bioflux"}) do
    local item=data.raw[kind] and data.raw[kind][name]
    if item then item.stack_size=1000000 end
  end
end
-- Retain native recycling, but keep products in its inventory for a pure
-- machine comparison instead of dropping thousands of item-on-ground entities.
data.raw.furnace.recycler.vector_to_place_result=nil
local pole=table.deepcopy(data.raw["electric-pole"].substation)
pole.name="upcycler-benchmark-supply"
pole.supply_area_distance=24
pole.maximum_wire_distance=64
data:extend{pole}
