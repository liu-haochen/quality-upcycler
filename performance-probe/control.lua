local specification=require("case")
local function inventory(e) return e.get_inventory(defines.inventory.crafter_input) end
local function outputs(e)
  return e.name=="quality-upcycler" and e.get_inventory(defines.inventory.crafter_trash) or e.get_output_inventory()
end
local function snapshot()
  local result={crafts=0,crafting=0,powered=0,min_finished=nil,max_finished=0,inputs=0,outputs=0}
  for _,e in ipairs(storage.entities) do
    local finished=e.products_finished
    result.crafts=result.crafts+finished
    result.min_finished=math.min(result.min_finished or finished,finished)
    result.max_finished=math.max(result.max_finished,finished)
    if e.is_crafting() then result.crafting=result.crafting+1 end
    if e.energy>0 then result.powered=result.powered+1 end
    for _,item in pairs(inventory(e).get_contents()) do result.inputs=result.inputs+item.count end
    for _,item in pairs(outputs(e).get_contents()) do result.outputs=result.outputs+item.count end
  end
  return result
end
script.on_init(function()
  storage.spec=specification
  storage.entities={}
  game.map_settings.pollution.enabled=false
  game.map_settings.enemy_expansion.enabled=false
  local surface=game.surfaces[1]
  surface.request_to_generate_chunks({224,224},9);surface.force_generate_chunk_requests()
  for _,e in pairs(surface.find_entities()) do e.destroy() end
  local tiles={}
  for x=-8,480 do for y=-8,480 do tiles[#tiles+1]={name="lab-dark-1",position={x,y}} end end
  surface.set_tiles(tiles)
  for _,quality in pairs(prototypes.quality) do game.forces.player.unlock_quality(quality.name) end
  -- Native recycling recipes are hidden technology unlocks. Enable recipes
  -- without researching productivity/speed bonuses that would change cadence.
  for _,recipe in pairs(game.forces.player.recipes) do recipe.enabled=true end
  local options=storage.spec
  local columns=math.ceil(math.sqrt(math.max(1,options.count)))
  local rows=math.ceil(options.count/columns)
  for y=0,math.ceil(rows/8)-1 do
    for x=0,math.ceil(columns/8)-1 do
      assert(surface.create_entity{name="upcycler-benchmark-supply",position={x*48+21,y*48+21},force="player"})
    end
  end
  if options.count>0 then
    local power=assert(surface.create_entity{name="electric-energy-interface",position={0,-3},force="player"})
    power.electric_buffer_size=1000000000000;power.power_production=1000000000000
  end
  local entity_name=({upcycler="quality-upcycler",assembler="assembling-machine-3",vanilla="assembling-machine-3",recycler="recycler"})[options.kind]
  for i=1,options.count do
    local x=(i-1)%columns*6;local y=math.floor((i-1)/columns)*6
    local e=assert(surface.create_entity{name=entity_name,position={x,y},force="player",raise_built=true})
    if options.kind~="vanilla" then e.get_module_inventory().insert{name="quality-module-3",count=4} end
    if options.kind=="assembler" then e.set_recipe("upcycler-benchmark-"..options.item)
    elseif options.kind=="vanilla" then e.set_recipe("iron-gear-wheel") end
    if options.mode~="idle" then
      local input=options.kind=="vanilla" and "iron-plate" or options.item
      assert(inventory(e).insert{name=input,count=1000000}==1000000,"Could not preload inputs")
    end
    if options.mode=="blocked" then
      local name=options.kind=="recycler" and "iron-plate" or options.item
      local output=outputs(e)
      for slot=1,#output do assert(output[slot].set_stack{name=name,count=1000000}) end
    end
    storage.entities[i]=e
  end
end)
script.on_event(defines.events.on_tick,function(event)
  local options=storage.spec;local tick=event.tick
  if tick==61 and options.mode=="active" then
    -- Distribute cycle phases once during warmup. The measured steady state
    -- has no harness iteration, feeding, draining or progress modification.
    for i,e in ipairs(storage.entities) do
      if e.is_crafting() then e.crafting_progress=(i*37%100)/100 end
    end
  elseif tick==options.warmup then storage.before=snapshot()
  elseif tick==options.ticks then
    local after=snapshot();local before=assert(storage.before)
    local completed=after.crafts-before.crafts
    assert(after.powered==options.count,"Benchmark machines were not all powered")
    if options.mode=="active" and options.count>0 then
      if not (after.min_finished>before.max_finished) then
        local debug={before=before,after=after,machines={}}
        for i=1,math.min(10,#storage.entities) do
          local e=storage.entities[i]
          debug.machines[i]={finished=e.products_finished,status=e.status,crafting=e.is_crafting(),energy=e.energy,
            input=inventory(e).get_contents(),output=outputs(e).get_contents(),slots=#outputs(e)}
        end
        error("Some benchmark machines stopped crafting: "..helpers.table_to_json(debug))
      end
      assert(after.inputs>options.count*900000,"Benchmark ran out of input")
    else assert(completed==0,"Idle/blocked benchmark unexpectedly crafted") end
    helpers.write_file("performance-"..options.label..".json",helpers.table_to_json{
      spec=options,before=before,after=after,completed=completed,
      crafts_per_machine_per_second=options.count>0 and completed/options.count/((options.ticks-options.warmup)/60) or 0
    },false)
  end
end)
