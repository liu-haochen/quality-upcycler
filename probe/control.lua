local function output(e) return e.get_inventory(defines.inventory.crafter_trash) end
local function state(e) return remote.call("quality-upcycler","get_state",e.unit_number) end
local kernel=require("__quality-upcycler__/kernel")
local costs=require("costs")
local perishables=require("perishables")
script.on_init(function()
  costs.export()
  local unlocked=false
  for _,effect in pairs(prototypes.technology["quality-module"].effects) do
    if effect.type=="unlock-recipe" and effect.recipe=="quality-upcycler" then unlocked=true end
  end
  assert(unlocked,"quality module 1 does not unlock upcycler")
  local ingredients=prototypes.recipe["quality-upcycler"].ingredients
  assert(#ingredients==4 and ingredients[1].name=="steel-plate" and ingredients[1].amount==5
    and ingredients[2].name=="iron-gear-wheel" and ingredients[2].amount==10
    and ingredients[3].name=="electronic-circuit" and ingredients[3].amount==5
    and ingredients[4].name=="advanced-circuit" and ingredients[4].amount==5,"early-game recipe changed")
  local early=game.create_force("early-quality-probe")
  early.technologies["quality-module"].researched=true
  assert(early.recipes["quality-upcycler"].enabled,"quality module 1 research did not enable recipe")
  assert(prototypes.recipe["quality-upcycling-stack-inserter"].localised_name[2][1]=="entity-name.stack-inserter","stack inserter translation uses wrong namespace")
  assert(prototypes.recipe["quality-upcycling-assembling-machine-3"].localised_name[2][1]=="entity-name.assembling-machine-3","machine translation uses wrong namespace")
  assert(prototypes.recipe["quality-upcycling-iron-gear-wheel"].localised_name[2][1]=="item-name.iron-gear-wheel","ordinary item translation changed")
  local counts={}
  for ticket=1,kernel.total do
    local result=kernel.draw(ticket)
    local key=result==nil and "destroy" or tostring(result)
    counts[key]=(counts[key] or 0)+1
  end
  assert(counts.destroy==270000 and counts["0"]==81000 and counts["1"]==44100 and counts["2"]==4410 and counts["3"]==441 and counts["4"]==49)
  for _,q in ipairs({0,0.01,0.04,0.08,0.1,0.128,0.16,0.188,0.248,0.25,0.99,1,2}) do
    for n=3,5 do
      local p=kernel.profile(q,n)
      for i=1,n do
        local total=p.destroy[i]
        for j=1,n do assert(p.rows[i][j]>=0);total=total+p.rows[i][j] end
        assert(math.abs(total-1)<1e-8)
      end
      if q>0 then for i=1,n-1 do for j=i+1,n do assert(p.rows[i][j]>0,"missing multi-tier upgrade") end end end
      if q>=1 then assert(p.destroy[1]==0 and p.rows[1][1]==0) end
    end
  end
  local baseline=kernel.profile(0.1,5)
  for j=1,5 do assert(math.abs(baseline.rows[1][j]-kernel.weights[j+1]/kernel.total)<1e-9) end
  assert(math.abs((1-baseline.rows[1][1])/(1-baseline.rows[1][1]-baseline.destroy[1])-319/49)<1e-8,"single-tier cost changed")
  for _,quality in pairs(prototypes.quality) do game.forces.player.unlock_quality(quality.name) end
  local surface=game.surfaces[1]
  surface.request_to_generate_chunks({0,0},2);surface.force_generate_chunk_requests()
  for _,e in pairs(surface.find_entities_filtered{area={{-30,-30},{45,30}}}) do e.destroy() end
  local tiles={};for x=-30,45 do for y=-30,30 do tiles[#tiles+1]={name="lab-dark-1",position={x,y}} end end
  surface.set_tiles(tiles)
  local function create(name,x,y,direction)
    local e=surface.create_entity{name=name,position={x,y},direction=direction or defines.direction.north,force="player",raise_built=true}
    if name=="quality-upcycler" then assert(e.get_module_inventory().insert{name="quality-module-3",count=4}==4,"quality modules rejected") end
    return e
  end
  local powered=create("quality-upcycler",0,0)
  create("medium-electric-pole",2,0)
  local power=create("electric-energy-interface",2,2)
  power.power_production=100000000;power.electric_buffer_size=100000000
  local source=create("steel-chest",0,-3)
  source.insert{name="iron-gear-wheel",count=500}
  create("fast-inserter",0,-2,defines.direction.north)
  local unpowered=create("quality-upcycler",20,0)
  unpowered.get_inventory(defines.inventory.crafter_input).insert{name="iron-gear-wheel",count=10}
  local slots=output(powered)
  assert(#slots==12,"expected twelve output slots")
  -- Manually verify several qualities can occupy the output simultaneously.
  for _,quality in ipairs({"normal","uncommon","rare","epic","legendary"}) do
    assert(slots.insert{name="iron-gear-wheel",quality=quality,count=1}==1,"mixed quality output rejected")
  end
  assert(#slots.get_contents()==5,"qualities failed to coexist")
  slots.clear()
  storage.powered=powered;storage.unpowered=unpowered
  storage.source=source
  storage.counts=counts
  local blocked=create("quality-upcycler",40,0)
  create("medium-electric-pole",42,0)
  local blocked_power=create("electric-energy-interface",42,2)
  blocked_power.power_production=100000000;blocked_power.electric_buffer_size=100000000
  assert(blocked.get_inventory(defines.inventory.crafter_input).insert{name="iron-gear-wheel",count=10}==10)
  local blocked_output=output(blocked)
  for _,name in ipairs({"stone","coal","iron-plate","copper-plate","steel-plate","iron-ore","copper-ore","stone-brick","iron-stick","copper-cable","electronic-circuit","plastic-bar"}) do
    local count=prototypes.item[name].stack_size
    assert(blocked_output.insert{name=name,count=count}==count,"could not fill output inventory")
  end
  assert(blocked_output.get_insertable_count{name="iron-gear-wheel"}==0,"test output not actually full")
  storage.blocked=blocked
  local switching=create("quality-upcycler",0,14)
  create("medium-electric-pole",2,14)
  local switch_power=create("electric-energy-interface",2,16)
  switch_power.power_production=100000000;switch_power.electric_buffer_size=100000000
  local switch_source=create("steel-chest",0,11)
  switch_source.insert{name="iron-plate",count=100}
  local switch_arm=create("fast-inserter",0,12,defines.direction.north)
  output(switching).insert{name="iron-plate",quality="normal",count=1}
  output(switching).insert{name="iron-plate",quality="uncommon",count=1}
  storage.switching=switching;storage.switch_source=switch_source;storage.switch_arm=switch_arm
  local progress=create("quality-upcycler",20,14)
  create("medium-electric-pole",22,14)
  local progress_power=create("electric-energy-interface",22,16)
  progress_power.power_production=100000000;progress_power.electric_buffer_size=100000000
  progress.get_inventory(defines.inventory.crafter_input).insert{name="rocket-silo",count=10}
  storage.progress=progress
  local recycler=create("recycler",25,14)
  recycler.get_module_inventory().insert{name="quality-module-3",count=4}
  storage.recycler=recycler
  local no_modules=create("quality-upcycler",20,-14)
  no_modules.get_module_inventory().clear()
  create("medium-electric-pole",22,-14)
  local nm_power=create("electric-energy-interface",22,-16)
  nm_power.power_production=100000000;nm_power.electric_buffer_size=100000000
  no_modules.get_inventory(defines.inventory.crafter_input).insert{name="iron-gear-wheel",count=100}
  storage.no_modules=no_modules
  local native=create("quality-upcycler-native-probe",30,14)
  create("medium-electric-pole",32,14)
  local native_power=create("electric-energy-interface",32,16)
  native_power.power_production=100000000;native_power.electric_buffer_size=100000000
  native.get_module_inventory().insert{name="quality-module-3",count=4}
  output(native).insert{name="iron-plate",quality="normal",count=1}
  output(native).insert{name="iron-plate",quality="uncommon",count=1}
  native.get_inventory(defines.inventory.crafter_input).insert{name="iron-plate",count=100}
  storage.native=native
  -- Legacy buffered results must survive upgrading the mod on an old save.
  assert(progress.get_output_inventory().insert{name="iron-plate",quality="uncommon",count=7}==7)
  local low=create("quality-upcycler",40,14)
  low.get_module_inventory().clear()
  assert(low.get_module_inventory().insert{name="quality-module",count=4}==4)
  create("medium-electric-pole",42,14)
  local low_power=create("electric-energy-interface",42,16)
  low_power.power_production=100000000;low_power.electric_buffer_size=100000000
  low.get_inventory(defines.inventory.crafter_input).insert{name="iron-gear-wheel",count=100}
  storage.low=low
  local high=create("quality-upcycler",40,-14)
  high.get_module_inventory().clear()
  assert(high.get_module_inventory().insert{name="quality-module-3",quality="legendary",count=4}==4)
  create("medium-electric-pole",42,-14)
  local high_power=create("electric-energy-interface",42,-16)
  high_power.power_production=100000000;high_power.electric_buffer_size=100000000
  high.get_inventory(defines.inventory.crafter_input).insert{name="iron-gear-wheel",count=100}
  storage.high=high
  local guaranteed=create("quality-upcycler",-20,14)
  guaranteed.get_module_inventory().clear()
  assert(guaranteed.get_module_inventory().insert{name="upcycler-probe-quarter-module",count=4}==4)
  create("medium-electric-pole",-18,14)
  local guaranteed_power=create("electric-energy-interface",-18,16)
  guaranteed_power.power_production=100000000;guaranteed_power.electric_buffer_size=100000000
  guaranteed.get_inventory(defines.inventory.crafter_input).insert{name="iron-gear-wheel",count=100}
  storage.guaranteed=guaranteed
  perishables.setup(create)
end)
script.on_event(defines.events.on_tick,function(event)
  if event.tick==60 then
    local s=state(storage.progress)
    local nr,nq=storage.native.get_recipe()
    helpers.write_file("native-probe.json",helpers.table_to_json{progress=storage.native.crafting_progress,products=storage.native.products_finished,previous=storage.native.previous_recipe,recipe=nr and nr.name,quality=nq and nq.name,input=storage.native.get_inventory(defines.inventory.crafter_input).get_contents()},false)
    helpers.write_file("upcycler-progress-debug.json",helpers.table_to_json{state=s,input=storage.progress.get_inventory(defines.inventory.crafter_input).get_contents(),energy=storage.progress.energy,recipe_time=prototypes.recipe["quality-upcycling-rocket-silo"].energy},false)
    assert(s.job and s.progress>0 and s.progress<1,"native progress bar not updated")
    assert(math.abs(s.progress-s.job.progress)<1e-5,"native and scripted progress differ")
    assert(s.current_recipe=="quality-upcycling-rocket-silo" and s.alt_item=="rocket-silo","native Alt recipe missing")
    assert(math.abs(s.quality_rate-0.1)<1e-8,"module quality rate incorrect")
    assert(math.abs(s.crafting_speed-storage.recycler.crafting_speed)<1e-8,"speed differs from recycler")
    assert(prototypes.recipe["quality-upcycling-rocket-silo"].energy==prototypes.recipe["rocket-silo-recycling"].energy,"recipe duration differs from recycler")
    assert(output(storage.progress).get_item_count{name="iron-plate",quality="uncommon"}==7,"legacy buffered output lost")
    assert(storage.progress.get_output_inventory().is_empty(),"legacy output did not migrate")
    assert(math.abs(state(storage.low).quality_rate-0.04)<1e-8,"tier-one modules not applied")
    assert(state(storage.high).quality_rate>0.1,"module quality did not improve effect")
    helpers.write_file("upcycler-progress.json",helpers.table_to_json(s),false)
  elseif event.tick==600 then
    perishables.check()
  elseif event.tick==1000 then
    storage.switch_source.get_inventory(defines.inventory.chest).clear()
    storage.switching.get_inventory(defines.inventory.crafter_input).clear()
    storage.switch_arm.held_stack.clear()
    storage.switch_source.insert{name="iron-plate",quality="uncommon",count=100}
    storage.switch_before=state(storage.switching).stats.processed
  elseif event.tick==3000 then
    local e=storage.switching
    local recipe,quality=e.get_recipe()
    local checks={}
    for _,q in ipairs({"normal","uncommon","rare","epic","legendary"}) do
      local item={name="iron-plate",quality=q,count=1}
      checks[#checks+1]={quality=q,insertable_count=output(e).get_insertable_count{name="iron-plate",quality=q}}
    end
    helpers.write_file("upcycler-switch-debug.json",helpers.table_to_json{state=state(e),input=e.get_inventory(defines.inventory.crafter_input).get_contents(),output=output(e).get_contents(),source=storage.switch_source.get_inventory(defines.inventory.chest).get_contents(),arm_status=storage.switch_arm.status,held=storage.switch_arm.held_stack.valid_for_read and {name=storage.switch_arm.held_stack.name,quality=storage.switch_arm.held_stack.quality.name} or nil,recipe=recipe and recipe.name,recipe_quality=quality and quality.name,before=storage.switch_before,checks=checks},false)
    assert(state(e).stats.processed>storage.switch_before+5,"switching input quality blocked while old output remained")
    storage.switch_source.get_inventory(defines.inventory.chest).clear()
    e.get_inventory(defines.inventory.crafter_input).clear()
    storage.switch_arm.held_stack.clear()
    storage.switch_source.insert{name="copper-plate",quality="rare",count=100}
    storage.switch_item_before=state(e).stats.processed
  elseif event.tick==5000 then
    local e=storage.switching
    local arm=storage.switch_arm
    helpers.write_file("upcycler-switch-item-debug.json",helpers.table_to_json{state=state(e),input=e.get_inventory(defines.inventory.crafter_input).get_contents(),output=output(e).get_contents(),before=storage.switch_item_before,source=storage.switch_source.get_inventory(defines.inventory.chest).get_contents(),held=arm.held_stack.valid_for_read and {name=arm.held_stack.name,quality=arm.held_stack.quality.name} or nil,enabled=e.force.recipes["quality-upcycling-copper-plate"].enabled,arm_status=arm.status,previous=e.previous_recipe},false)
    assert(state(e).stats.processed>storage.switch_item_before+5,"switching item and quality blocked while old output remained")
    assert(output(e).get_item_count{name="iron-plate",quality="normal"}>0,"old output was unexpectedly cleared")
    storage.switch_source.get_inventory(defines.inventory.chest).clear()
    e.get_inventory(defines.inventory.crafter_input).clear()
    storage.switch_arm.held_stack.clear()
    storage.switch_source.insert{name="copper-plate",quality="legendary",count=10}
  elseif event.tick==6000 then
    local powered=storage.powered
    local s=state(powered)
    helpers.write_file("upcycler-debug.json",helpers.table_to_json{state=s,energy=powered.energy,input=powered.get_inventory(defines.inventory.crafter_input).get_contents(),source=storage.source.get_inventory(defines.inventory.chest).get_contents()},false)
    assert(s and s.stats.processed>=35,"powered/inserter-fed machine did not process")
    assert(s.stats.destroyed+s.stats.kept+s.stats.upgraded==s.stats.processed,"processing counters do not balance")
    assert(s.stats.upgraded+state(storage.switching).stats.upgraded>0,"no actual upgrade output observed")
    assert(state(storage.unpowered).stats.processed==0,"machine processed without power")
    assert(state(storage.no_modules).quality_rate==0 and state(storage.no_modules).stats.upgraded==0,"upgraded with no quality modules")
    local guaranteed=state(storage.guaranteed)
    assert(guaranteed.quality_rate==1 and guaranteed.stats.upgraded==100 and guaranteed.stats.destroyed==0 and guaranteed.stats.kept==0,"four 25-percent modules failed")
    helpers.write_file("upcycler-blocked-debug.json",helpers.table_to_json{state=state(storage.blocked),input=storage.blocked.get_inventory(defines.inventory.crafter_input).get_contents(),output=output(storage.blocked).get_contents()},false)
    assert(state(storage.blocked).stats.processed==0,"machine consumed inputs with no output room")
    assert(storage.blocked.get_inventory(defines.inventory.crafter_input).get_item_count("iron-gear-wheel")==10,"full-output input was consumed")
    assert(output(powered).get_item_count("iron-gear-wheel")>0,"no physical output")
    assert(state(storage.switching).stats.passed==10,"highest quality failed to pass through with old output present")
    local report={phase="buffer",stats=s.stats,outputs=output(powered).get_contents(),
      output_slots=#output(powered),no_power_processed=state(storage.unpowered).stats.processed,kernel_counts=storage.counts,
      switching_state=state(storage.switching),switching_outputs=output(storage.switching).get_contents(),
      module_profiles={none=state(storage.no_modules).quality_rate,normal_t1=state(storage.low).quality_rate,normal_t3=s.quality_rate,legendary_t3=state(storage.high).quality_rate,four_25_percent=guaranteed.quality_rate},guaranteed=guaranteed.stats}
    helpers.write_file("upcycler-buffer.json",helpers.table_to_json(report),false)
    -- Now use a real inserter to extract all buffered output.
    local surface=powered.surface
    storage.sink=surface.create_entity{name="steel-chest",position={0,3},force="player"}
    storage.output_arm=surface.create_entity{name="fast-inserter",position={0,2},direction=defines.direction.north,force="player"}
    output(storage.blocked).clear()
  elseif event.tick==9000 then
    assert(storage.sink.get_inventory(defines.inventory.chest).get_item_count("iron-gear-wheel")>0,"inserter could not extract output")
    assert(state(storage.blocked).stats.processed>0,"machine did not recover after output cleared")
    local s=state(storage.powered)
    local inputs=storage.source.get_inventory(defines.inventory.chest).get_item_count("iron-gear-wheel")
    helpers.write_file("upcycler-report.json",helpers.table_to_json{stats=s.stats,
      inserter_sink=storage.sink.get_inventory(defines.inventory.chest).get_contents(),source_remaining=inputs,
      no_power_processed=state(storage.unpowered).stats.processed},false)
  end
end)
