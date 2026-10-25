"""Save a running baseline machine, then load it with the optimized code."""
import json
from pathlib import Path
import shutil
import subprocess
import time
from zipfile import ZipFile,BadZipFile
import benchmark

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime-release/migration"
BINARY = "E:/steam/steamapps/common/Factorio/bin/x64/Factorio.exe"
save_name = f"upcycler-optimization-{time.time_ns()}"
optimized_save_name=save_name+"-optimized"
benchmark.RUNTIME = RUNTIME
benchmark.prepare(BINARY)
for label in [save_name,optimized_save_name]:
    for name in [label,label+".zip","_autosave-"+label+".zip"]:
        (RUNTIME / "saves" / name).touch()
probe = RUNTIME / "mods/quality-upcycler-performance-probe_0.1.0"
(probe / "data.lua").write_text('''data:extend{{type="module",name="migration-quality-module",icon="__quality__/graphics/icons/quality-module-3.png",subgroup="module",category="quality",tier=3,stack_size=50,effect={quality=0.25,speed=-0.05}}}''', encoding="utf-8")
(probe / "data-final-fixes.lua").write_text("-- No benchmark prototype changes in the migration test.\n", encoding="utf-8")
control = r'''
local function output(e) return e.get_inventory(defines.inventory.crafter_trash) end
local function state(e) return remote.call("quality-upcycler","get_state",e.unit_number) end
script.on_init(function()
  local surface=game.surfaces[1]
  surface.request_to_generate_chunks({0,0},2);surface.force_generate_chunk_requests()
  for _,e in pairs(surface.find_entities_filtered{area={{-5,-5},{35,8}}}) do e.destroy() end
  local tiles={};for x=-5,35 do for y=-5,8 do tiles[#tiles+1]={name="lab-dark-1",position={x,y}} end end;surface.set_tiles(tiles)
  for _,q in pairs(prototypes.quality) do game.forces.player.unlock_quality(q.name) end
  local function create(x,item)
    local e=surface.create_entity{name="quality-upcycler",position={x,0},force="player",raise_built=true}
    e.get_module_inventory().insert{name="migration-quality-module",count=4}
    surface.create_entity{name="medium-electric-pole",position={x+2,0},force="player"}
    local p=surface.create_entity{name="electric-energy-interface",position={x+2,2},force="player"};p.power_production=100000000;p.electric_buffer_size=100000000
    if item then e.get_inventory(defines.inventory.crafter_input).insert{name=item,count=1} end
    return e
  end
  storage.armor=create(0,"power-armor-mk2")
  local armor=storage.armor.get_inventory(defines.inventory.crafter_input)[1];armor.health=0.6
  local battery=armor.grid.put{name="battery-equipment",quality="rare",position={0,0}};battery.energy=1234
  storage.silo=create(10,"rocket-silo")
  storage.silo.get_inventory(defines.inventory.crafter_input)[1].health=0.4
  storage.idle=create(20)
  storage.blocked=create(30,"iron-gear-wheel")
  for i=1,#output(storage.blocked) do output(storage.blocked)[i].set_stack{name="stone",count=prototypes.item.stone.stack_size} end
end)
script.on_event(defines.events.on_tick,function(event)
  if event.tick==100 and not storage.save_requested then
    assert(storage.armor.is_crafting() and storage.silo.is_crafting(),"Baseline did not save during active jobs")
    assert(storage.armor.crafting_progress>0 and storage.armor.crafting_progress<1,"Armor already completed")
    storage.save_requested=true
    helpers.write_file("migration-before.json",helpers.table_to_json{armor=state(storage.armor),silo=state(storage.silo)},false)
    game.auto_save("SAVE_NAME")
  elseif event.tick==120 then
    storage.idle.get_inventory(defines.inventory.crafter_input).insert{name="iron-plate",count=5}
    output(storage.blocked).clear()
  elseif event.tick==500 and not storage.optimized_save_requested then
    storage.optimized_save_requested=true
    game.auto_save("SECOND_SAVE")
  elseif event.tick==1000 then
    local report={}
    for _,key in ipairs({"armor","silo","idle","blocked"}) do
      local e=storage[key];local s=state(e);local count=0;local stack
      for i=1,#output(e) do if output(e)[i].valid_for_read then stack=output(e)[i];count=count+stack.count end end
      local expected=key=="idle" and 5 or 1
      assert(count==expected and s.stats.processed==expected and s.stats.destroyed==0,"Migration lost or duplicated "..key)
      assert(stack.quality.name~="normal","Migration lost quality effect")
      if key=="armor" then
        assert(math.abs(stack.health-0.6)<0.0001 and #stack.grid.equipment==1,"Migration lost armor state")
        local eq=stack.grid.equipment[1];assert(eq.quality.name=="rare" and math.abs(eq.energy-1234)<0.01,"Migration lost equipment data")
      elseif key=="silo" then assert(math.abs(stack.health-0.4)<0.0001,"Migration lost source damage") end
      report[key]={count=count,quality=stack.quality.name,stats=s.stats}
    end
    helpers.write_file("migration-after.json",helpers.table_to_json(report),false)
  end
end)
'''.replace("SAVE_NAME", save_name).replace("SECOND_SAVE",optimized_save_name)
(probe / "control.lua").write_text(control, encoding="utf-8")
for name in ["migration-before.json", "migration-after.json"]:
    (RUNTIME / "script-output" / name).write_text("", encoding="utf-8")
installed = RUNTIME / "mods/quality-upcycler_0.1.0"
baseline = ROOT / "analysis/performance-optimization/baseline-source"
for path in baseline.glob("*.lua"):
    shutil.copy2(path, installed / path.name)
original = RUNTIME / "maps/baseline.zip"
benchmark.run_factorio(BINARY, ["--create", str(original), "--map-gen-seed", "13579"], RUNTIME / "logs/create.log")
settings=RUNTIME / "server-settings.json"
settings.write_text(json.dumps({"name":"Local upcycler migration check","description":"Isolated local test",
    "visibility":{"public":False,"lan":False},"require_user_verification":False,"auto_pause":False}),encoding="utf-8")
# Benchmark mode suppresses saving. Stop this private loopback server as soon
# as its mid-craft save has been fully written and verified.
def run_to_save(source,destination,label):
    command=[BINARY,"--config",str(RUNTIME/"config.ini"),"--mod-directory",str(RUNTIME/"mods"),
        "--start-server",str(source),"--bind","127.0.0.1:34221","--server-settings",str(settings)]
    with (RUNTIME/"logs"/label).open("w",encoding="utf-8") as log:
        process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0))
        ready=False
        try:
            deadline=time.monotonic()+20
            while time.monotonic()<deadline and process.poll() is None:
                if destination.stat().st_size>1000:
                    try:
                        with ZipFile(destination) as archive:ready=archive.testzip() is None
                    except (BadZipFile,OSError):pass
                    if ready:break
                time.sleep(0.1)
            assert ready,"Private server did not write a valid mid-craft save; see "+label
        finally:
            if process.poll() is None:
                process.terminate()
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:process.kill();process.wait()
saved_path=RUNTIME / "saves" / ("_autosave-"+save_name+".zip")
run_to_save(original,saved_path,"baseline.log")
assert saved_path.stat().st_size>1000, "Baseline autosave was not created"
for path in (ROOT / "mod").glob("*.lua"):
    shutil.copy2(path, installed / path.name)
optimized_path=RUNTIME/"saves"/("_autosave-"+optimized_save_name+".zip")
run_to_save(saved_path,optimized_path,"optimized-save.log")
benchmark.run_factorio(BINARY, ["--benchmark", str(optimized_path), "--benchmark-ticks", "650", "--benchmark-runs", "1"], RUNTIME / "logs/optimized.log")
before = json.loads((RUNTIME / "script-output/migration-before.json").read_text(encoding="utf-8-sig"))
after = json.loads((RUNTIME / "script-output/migration-after.json").read_text(encoding="utf-8-sig"))
report = {"saved_mid_craft_with_baseline": True, "loaded_with_optimized_code": True,"optimized_save_reloaded":True, "before": before, "after": after}
destination = ROOT / "analysis/performance-optimization/migration-report.json"
destination.write_text(json.dumps(report, indent=2), encoding="utf-8")
print("Baseline mid-craft save migrated successfully: armor/grid/energy, source health, idle and blocked recovery.")
