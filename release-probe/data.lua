local icon="__base__/graphics/icons/iron-plate.png"
data:extend{
  {type="item-with-tags",name="upcycler-release-tagged",icon=icon,subgroup="raw-material",stack_size=1,flags={"not-stackable"}},
  {type="item-with-inventory",name="upcycler-release-container",icon=icon,subgroup="raw-material",stack_size=1,inventory_size=8,flags={"not-stackable"}},
  {type="module",name="upcycler-release-power-module",icon="__quality__/graphics/icons/quality-module-3.png",subgroup="module",
    category="quality",tier=3,stack_size=50,effect={quality=0.25,speed=-0.05,consumption=0.5,pollution=0.25}}
}
