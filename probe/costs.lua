local M={}
function M.export()
  local leaves={ ["iron-plate"]=true,["copper-plate"]=true,["plastic-bar"]=true,["stone-brick"]=true }
  local function add(target,source,factor)
    for name,amount in pairs(source) do target[name]=(target[name] or 0)+amount*factor end
  end
  local cache={}
  local function expand(name)
    if leaves[name] then return {[name]=1} end
    if cache[name] then return cache[name] end
    local recipe=assert(prototypes.recipe[name],"missing cost recipe: "..name)
    assert(#recipe.products==1 and recipe.products[1].amount,"non-deterministic comparison recipe")
    local result={}
    for _,ingredient in pairs(recipe.ingredients) do
      assert(ingredient.type=="item","fluid outside cost comparison boundary")
      add(result,expand(ingredient.name),ingredient.amount/recipe.products[1].amount)
    end
    cache[name]=result
    return result
  end
  local report={basis="Installed base/Space Age recipes; no productivity; iron/copper plates, plastic and stone bricks as boundary",recipes={}}
  for _,name in ipairs({"assembling-machine-1","assembling-machine-2","chemical-plant","electric-furnace","oil-refinery","beacon","quality-module","quality-upcycler"}) do
    report.recipes[name]={ingredients=prototypes.recipe[name].ingredients,expanded=expand(name)}
  end
  report.previous_upcycler={}
  add(report.previous_upcycler,expand("iron-plate"),50)
  add(report.previous_upcycler,expand("electronic-circuit"),20)
  add(report.previous_upcycler,expand("advanced-circuit"),10)
  report.new_with_four_t1={}
  add(report.new_with_four_t1,expand("quality-upcycler"),1)
  add(report.new_with_four_t1,expand("quality-module"),4)
  helpers.write_file("recipe-cost-comparison.json",helpers.table_to_json(report),false)
end
return M
