local e=table.deepcopy(data.raw.furnace["quality-upcycler"])
e.name="quality-upcycler-native-probe"
e.show_recipe_icon=true
e.minable=nil
data:extend{e}
data:extend{{type="module",name="upcycler-probe-quarter-module",icon="__quality__/graphics/icons/quality-module-3.png",subgroup="module",category="quality",tier=3,stack_size=50,effect={quality=0.25,speed=-0.05}}}
data:extend{
  {type="item",name="upcycler-probe-fast-spoil",icon="__space-age__/graphics/icons/nutrients.png",subgroup="raw-material",stack_size=100,spoil_ticks=120,spoil_result="spoilage"},
  {type="recipe",name="upcycler-probe-fast-spoil",enabled=true,energy_required=16,auto_recycle=false,ingredients={{type="item",name="spoilage",amount=1}},results={{type="item",name="upcycler-probe-fast-spoil",amount=1}}}
}
