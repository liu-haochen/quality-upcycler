local assembler=data.raw["assembling-machine"]["assembling-machine-3"]
local upcycler=data.raw.furnace["quality-upcycler"]
for _,product in ipairs(data.raw.recipe["iron-gear-wheel-recycling"].results) do product.affected_by_quality=false end
for _,item in ipairs({"iron-gear-wheel","processing-unit","firearm-magazine","automation-science-pack","bioflux"}) do
  local source=assert(data.raw.recipe["quality-upcycling-"..item])
  data:extend{{type="recipe",name="upcycler-benchmark-"..item,enabled=true,hidden=true,
    energy_required=source.energy_required*assembler.crafting_speed/upcycler.crafting_speed,
    auto_recycle=false,allow_productivity=false,allow_quality=true,
    ingredients={{type="item",name=item,amount=1}},
    -- Assemblers expose one result slot for this recipe. Keep the control
    -- output normal so it cannot stall on mixed qualities without inserters.
    results={{type="item",name=item,amount=1,independent_probability=0.325,affected_by_quality=false}}}}
end
