local M={}
function M.setup(create)
  local fixtures={}
  local function fixture(name,x,y,count,spoil)
    local e=create("quality-upcycler",x,y)
    e.get_module_inventory().clear()
    assert(e.get_module_inventory().insert{name="upcycler-probe-quarter-module",count=4}==4)
    create("medium-electric-pole",x+2,y)
    local power=create("electric-energy-interface",x+2,y+2)
    power.power_production=100000000;power.electric_buffer_size=100000000
    assert(e.get_inventory(defines.inventory.crafter_input).insert{name=name,count=count,spoil_percent=spoil}==count,"perishable input refused: "..name)
    e.get_inventory(defines.inventory.crafter_input)[1].spoil_percent=spoil
    assert(math.abs(e.get_inventory(defines.inventory.crafter_input)[1].spoil_percent-spoil)<0.0001)
    if name=="bioflux" then
      local source=create("steel-chest",x,y-3)
      source.get_inventory(defines.inventory.chest)[1].transfer_stack(e.get_inventory(defines.inventory.crafter_input)[1])
      create("fast-inserter",x,y-2,defines.direction.north)
      create("medium-electric-pole",x+2,y-3)
    end
    fixtures[#fixtures+1]={entity=e,name=name,count=count,spoil=spoil}
  end
  fixture("bioflux",-20,-14,10,0.6)
  fixture("agricultural-science-pack",-8,-14,5,0.8)
  fixture("biter-egg",4,-14,5,0.5)
  fixture("yumako",-8,0,10,0.4)
  fixture("nutrients",4,14,10,0.75)
  fixture("upcycler-probe-fast-spoil",-20,0,1,0)
  storage.perishables=fixtures
end
function M.check()
  local report={}
  for _,fixture in ipairs(storage.perishables) do
    local e=fixture.entity
    local inventory=e.get_inventory(defines.inventory.crafter_trash)
    local count=0;local stacks={}
    for i=1,#inventory do
      local stack=inventory[i]
      if stack.valid_for_read and stack.name==fixture.name then
        count=count+stack.count
        stacks[#stacks+1]={quality=stack.quality.name,count=stack.count,spoil_percent=stack.spoil_percent}
        if fixture.name~="upcycler-probe-fast-spoil" then
          assert(stack.quality.name~="normal","100% module rate did not upgrade perishables")
          assert(stack.spoil_percent>=fixture.spoil-0.0001,"freshness was reset: "..fixture.name.." "..stack.spoil_percent)
          assert(stack.spoil_percent<fixture.spoil+0.05,"unexpected spoilage increase: "..fixture.name)
        end
      end
    end
    if fixture.name=="upcycler-probe-fast-spoil" then
      assert(count==0,"expired item was refreshed during crafting")
    else assert(count==fixture.count,"perishable output lost or duplicated: "..fixture.name) end
    report[#report+1]={name=fixture.name,outputs=stacks,state=remote.call("quality-upcycler","get_state",e.unit_number)}
  end
  helpers.write_file("upcycler-perishables.json",helpers.table_to_json(report),false)
end
return M
