local function output(e) return e.get_inventory(defines.inventory.crafter_trash) end
local item_state=require("__quality-upcycler__/item-state")
local function state(e) return remote.call("quality-upcycler","get_state",e.unit_number) end
local function near(a,b) assert(math.abs(a-b)<0.0001,tostring(a).." ~= "..tostring(b)) end
script.on_init(function()
  local surface=game.create_surface("upcycler-release-checks",{autoplace_controls={}})
  surface.request_to_generate_chunks({0,0},4);surface.force_generate_chunk_requests()
  local tiles={};for x=-5,145 do for y=-8,8 do tiles[#tiles+1]={name="lab-dark-1",position={x,y}} end end
  surface.set_tiles(tiles)
  storage.cases={}
  local function machine(name,configure,options)
    options=options or {}
    assert(prototypes.recipe["quality-upcycling-"..name],"No recipe for "..name)
    local i=#storage.cases+1;local x=i*5
    local e=surface.create_entity{name="quality-upcycler",position={x,0},quality=options.machine_quality or "normal",force="player",raise_built=true}
    surface.create_entity{name="medium-electric-pole",position={x+2,0},force="player"}
    local power=surface.create_entity{name="electric-energy-interface",position={x+2,2},force="player"}
    power.power_production=100000000;power.electric_buffer_size=100000000
    e.get_module_inventory().insert{name=options.power_module and "upcycler-release-power-module" or "upcycler-probe-quarter-module",count=4}
    local inv=e.get_inventory(defines.inventory.crafter_input)
    assert(inv.insert{name=name,count=options.count or 1,quality=options.quality or "normal"}==(options.count or 1),"Rejected "..name)
    if configure then configure(inv[1]) end
    local case={name=name,entity=e,count=options.count or 1,quality=options.quality or "normal",power_module=options.power_module,ammo=options.ammo}
    storage.cases[#storage.cases+1]=case
    return e,case
  end
  for _,name in ipairs({"firearm-magazine","piercing-rounds-magazine","uranium-rounds-magazine","atomic-bomb","submachine-gun",
    "light-armor","battery-equipment","rail","space-platform-starter-pack","automation-science-pack","chemical-science-pack",
    "production-science-pack","promethium-science-pack","quality-upcycler"}) do machine(name) end
  machine("firearm-magazine",function(stack) stack.ammo=3 end,{ammo=3})
  machine("repair-pack",function(stack) stack.durability=stack.prototype.get_durability(stack.quality)*0.4 end)
  machine("iron-plate",function(stack) stack.health=0.45 end)
  machine("bioflux",function(stack) stack.spoil_percent=0.25 end)
  local function equip(stack)
    stack.health=0.6
    local grid=stack.grid or stack.create_grid()
    local battery=assert(grid.put{name="battery-equipment",quality="rare",position={0,0}});battery.energy=1234
    local battery2=assert(grid.put{name="battery-equipment",quality="uncommon",position={2,0}});battery2.energy=4321
  end
  machine("power-armor-mk2",equip)
  machine("power-armor-mk2",equip,{quality="legendary"})
  machine("spidertron",function(stack)
    equip(stack);stack.entity_label="Release probe";stack.entity_color={r=0.2,g=0.4,b=0.6,a=1}
    stack.entity_logistics_enabled=false
  end)
  machine("upcycler-release-tagged",function(stack)
    stack.tags={serial="keep-me",nested={number=42}};stack.custom_description="Release test";stack.label="Tagged input"
  end)
  machine("upcycler-release-container",function(stack)
    stack.label="Container input"
    local inv=stack.get_inventory(defines.inventory.item_main)
    inv[2].set_stack{name="iron-plate",quality="epic",count=7}
    inv[4].set_stack{name="upcycler-release-tagged",count=1,tags={nested="untouched"}}
  end)
  machine("rocket-silo",nil,{power_module=true})
  -- A real inserter supplies a partially used magazine followed by a full one.
  local e,case=machine("firearm-magazine",nil,{count=1})
  e.get_inventory(defines.inventory.crafter_input).clear();case.arm_fed=true;case.count=2
  local x=e.position.x
  local chest=surface.create_entity{name="steel-chest",position={x,-3},force="player"}
  chest.insert{name="firearm-magazine",count=2,ammo=3}
  surface.create_entity{name="fast-inserter",position={x,-2},direction=defines.direction.north,force="player"}
  storage.arm_source=chest
  storage.fast_machine=machine("copper-cable",nil,{count=200,machine_quality="legendary"})
  storage.pending_machine=machine("rocket-silo")
  local mining=machine("power-armor-mk2",equip)
  table.remove(storage.cases)
  storage.mining=mining
  storage.mining_state={}
  item_state.capture(storage.mining_state,mining.get_inventory(defines.inventory.crafter_input)[1])
  local p=prototypes.entity["quality-upcycler"]
  near(p.energy_usage*60,360000)
  near(p.electric_energy_source_prototype.drain*60,12000)
  near(p.get_crafting_speed("normal"),prototypes.entity.recycler.get_crafting_speed("normal"))
  assert(not prototypes.recipe["quality-upcycling-blueprint"],"UI blueprint should not be consumed")
end)
script.on_event(defines.events.on_tick,function(event)
  if event.tick==180 then
    assert(storage.fast_machine.products_finished>180,"High-quality fast machine was limited to one craft per tick")
  end
  if event.tick==10 then
    local e=storage.mining
    assert(e.crafting_progress>0,"Mining test did not interrupt a craft")
    local next_input=e.get_inventory(defines.inventory.crafter_input)
    assert(next_input.insert{name="power-armor-mk2",count=1}==1)
    next_input[1].health=0.8
    assert(next_input[1].grid.put{name="battery-equipment",quality="legendary",position={0,0}})
    -- Headless runs have no player, so exercise the production refund helper
    -- on the actual buffer returned by native mining. Event wiring is manual.
    local mined_inventory=game.create_inventory(40)
    assert(e.mine{inventory=mined_inventory,force=true},"Mining failed")
    local refund=item_state.refund(storage.mining_state,mined_inventory)
    assert(mined_inventory.insert(refund.stack[1])==1,"Could not return original input")
    refund.stack.destroy()
    local found=false;local extra=false;local armor_count=0
    for i=1,#mined_inventory do
      local stack=mined_inventory[i]
      if stack.valid_for_read and stack.name=="power-armor-mk2" then
        armor_count=armor_count+1
        if math.abs(stack.health-0.6)<0.0001 then
          assert(stack.grid and #stack.grid.equipment==2,"Mining lost installed equipment");found=true
        elseif math.abs(stack.health-0.8)<0.0001 then
          assert(stack.grid and #stack.grid.equipment==1 and stack.grid.equipment[1].quality.name=="legendary","Mining replaced a different input");extra=true
        end
      end
    end
    assert(found and extra and armor_count==2,"Mining lost or duplicated an input")
    local pending=storage.pending_machine
    assert(pending.crafting_progress>0,"Pending test did not interrupt an active craft")
    for i=1,#output(pending) do output(pending)[i].set_stack{name="stone",count=prototypes.item.stone.stack_size} end
  end
  if event.tick==700 then
    local s=state(storage.pending_machine)
    assert(s.stats.processed==1 and #s.pending==1,"Blocked completed craft was lost or repeated")
    output(storage.pending_machine).clear()
  elseif event.tick==702 then
    local s=state(storage.pending_machine)
    local count=0
    for _,item in pairs(output(storage.pending_machine).get_contents()) do if item.name=="rocket-silo" then count=count+item.count end end
    assert(s.stats.processed==1 and #s.pending==0 and count==1,"Output recovery rerolled or lost a result")
  end
  if event.tick~=9000 then return end
  local report={cases={},energy_kw=360,drain_kw=12,mining_refund_helper=true}
  local expected_production={}
  for _,case in ipairs(storage.cases) do
    local e=case.entity;local inv=output(e);local count=0;local stack
    local ammo=0
    for i=1,#inv do if inv[i].valid_for_read then
      stack=inv[i];assert(stack.name==case.name,"Wrong output item")
      assert(case.quality=="legendary" and stack.quality.name=="legendary" or stack.quality.level>0,"Failed to upgrade "..case.name)
      count=count+stack.count
      expected_production[stack.name]=expected_production[stack.name] or {}
      local qualities=expected_production[stack.name]
      qualities[stack.quality.name]=(qualities[stack.quality.name] or 0)+stack.count
      if case.arm_fed then ammo=ammo+stack.ammo+(stack.count-1)*stack.prototype.magazine_size end
    end end
    assert(count==case.count,case.name.." output count "..count..", expected "..case.count)
    local s=state(e)
    assert(s.stats.destroyed==0 and s.stats.kept==0,"100% modules lost or retained an input")
    if case.name=="firearm-magazine" and case.arm_fed then near(ammo,13)
    elseif case.name=="firearm-magazine" and not case.arm_fed then near(stack.ammo,case.ammo or 10)
    elseif case.name=="repair-pack" then near(stack.durability/stack.prototype.get_durability(stack.quality),0.4)
    elseif case.name=="iron-plate" then near(stack.health,0.45)
    elseif case.name=="power-armor-mk2" or case.name=="spidertron" then
      near(stack.health,0.6);assert(#stack.grid.equipment==2,"Lost grid equipment")
      for _,equipment in pairs(stack.grid.equipment) do
        if equipment.position.x==0 then assert(equipment.quality.name=="rare");near(equipment.energy,1234)
        else assert(equipment.quality.name=="uncommon");near(equipment.energy,4321) end
      end
      if case.name=="spidertron" then assert(stack.entity_label=="Release probe");near(stack.entity_color.g,0.4);assert(not stack.entity_logistics_enabled) end
    elseif case.name=="upcycler-release-tagged" then
      assert(stack.tags.serial=="keep-me" and stack.tags.nested.number==42 and stack.label=="Tagged input" and stack.custom_description=="Release test")
    elseif case.name=="upcycler-release-container" then
      local inner=stack.get_inventory(defines.inventory.item_main)
      assert(inner[2].count==7 and inner[2].quality.name=="epic" and inner[4].tags.nested=="untouched" and stack.label=="Container input")
    end
    if case.power_module then near(e.consumption_bonus,2);assert(s.stats.processed==1,"Consumption modules starved the machine") end
    report.cases[#report.cases+1]={name=case.name,quality=stack.quality.name,count=count,arm_fed=case.arm_fed,stats=s.stats}
  end
  local statistics=game.forces.player.get_item_production_statistics("upcycler-release-checks")
  for name,qualities in pairs(expected_production) do
    for _,quality in pairs(prototypes.quality) do
      near(statistics.get_input_count{name=name,quality=quality.name},qualities[quality.name] or 0)
    end
  end
  report.production_statistics=true
  helpers.write_file("upcycler-release-report.json",helpers.table_to_json(report),false)
end)
