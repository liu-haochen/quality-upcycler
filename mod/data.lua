local assembler=data.raw["assembling-machine"]["assembling-machine-3"]
local machine=table.deepcopy(data.raw.furnace.recycler)
machine.name="quality-upcycler"
machine.localised_name={"entity-name.quality-upcycler"}
machine.localised_description={"entity-description.quality-upcycler"}
machine.icon="__quality-upcycler__/graphics/quality-upcycler-icon.png"
machine.icon_size=64
machine.minable={mining_time=0.3,result="quality-upcycler"}
machine.fast_replaceable_group=nil
machine.next_upgrade=nil
machine.collision_box=table.deepcopy(assembler.collision_box)
machine.selection_box=table.deepcopy(assembler.selection_box)
machine.graphics_set=require("graphics.animation")
machine.graphics_set_flipped=nil
machine.use_mirroring=false
machine.working_sound=table.deepcopy(assembler.working_sound)
machine.corpse=assembler.corpse
machine.dying_explosion=assembler.dying_explosion
machine.water_reflection=nil
machine.circuit_connector=table.deepcopy(assembler.circuit_connector)
machine.circuit_connector_flipped=nil
machine.vector_to_place_result=nil
machine.crafting_categories={"quality-upcycling"}
machine.source_inventory_size=1
-- Keep the old inventory so existing saves cannot lose buffered products.
-- Runtime migrates it to the unrestricted byproduct inventory below.
machine.result_inventory_size=12
machine.trash_inventory_size=12
machine.crafting_speed=data.raw.furnace.recycler.crafting_speed
-- Two quality attempts in one machine cost twice a recycler's active power.
-- Let the engine size the electric buffer; a fixed input limit can otherwise
-- starve machines when a quality module adds a consumption penalty.
machine.energy_usage="360kW"
machine.energy_source={type="electric",usage_priority="secondary-input",drain="12kW",emissions_per_minute={pollution=4}}
machine.heating_energy="100kW"
machine.module_slots=4
machine.allowed_effects={"quality","speed","consumption","pollution"}
machine.allowed_module_categories={"quality"}
machine.effect_receiver={uses_beacon_effects=false}
machine.show_recipe_icon=true
machine.icon_draw_specification=nil
machine.icons_positioning=nil
machine.custom_input_slot_tooltip_key="quality-upcycler.input-tooltip"
machine.cant_insert_at_source_message_key="quality-upcycler.unsupported"
data:extend{
  machine,
  {type="recipe-category",name="quality-upcycling"},
  {type="item",name="quality-upcycler",icon=machine.icon,icon_size=64,subgroup="production-machine",order="z[quality-upcycler]",place_result="quality-upcycler",stack_size=20,weight=100000},
  {type="recipe",name="quality-upcycler",enabled=false,energy_required=10,
    ingredients={{type="item",name="steel-plate",amount=5},{type="item",name="iron-gear-wheel",amount=10},{type="item",name="electronic-circuit",amount=5},{type="item",name="advanced-circuit",amount=5}},
    results={{type="item",name="quality-upcycler",amount=1}}},
  -- Retain the old technology only as a hidden save-compatibility record.
  {type="technology",name="quality-upcycling",hidden=true,icon="__quality__/graphics/technology/quality-module-1.png",icon_size=256,
    prerequisites={"quality-module"},effects={{type="unlock-recipe",recipe="quality-upcycler"}},
    unit={count=1,time=1,ingredients={{"automation-science-pack",1}}}}
}
table.insert(data.raw.technology["quality-module"].effects,{type="unlock-recipe",recipe="quality-upcycler"})
