local M={}
-- Exact integer reference for q=10%, five qualities.
M.total=400000
M.weights={270000,81000,44100,4410,441,49}
local cache={}
function M.profile(q,n)
  q=math.max(0,math.min(1,q))
  local by_quality=cache[n]
  if not by_quality then by_quality={};cache[n]=by_quality end
  if by_quality[q] then return by_quality[q] end
  -- First quality attempt succeeds without a recycling loss. If it fails,
  -- 75% is lost; the surviving 25% gets a second quality attempt.
  local destroy=0.75*(1-q)
  local stay=0.25*(1-q)^2
  local upgrade=q+0.25*(1-q)*q
  local rows,deaths={},{}
  for i=1,n do
    rows[i]={};for j=1,n do rows[i][j]=0 end
    if i==n then rows[i][i]=1;deaths[i]=0
    else
      deaths[i]=destroy;rows[i][i]=stay
      for j=i+1,n do
        rows[i][j]=upgrade*0.1^(j-i-1)*(j==n and 1 or 0.9)
      end
    end
  end
  local p={q=q,rows=rows,destroy=deaths}
  by_quality[q]=p
  return p
end
function M.choose(profile,rank,u)
  local cumulative=profile.destroy[rank]
  if u<cumulative then return nil end
  for j=rank,#profile.rows do
    cumulative=cumulative+profile.rows[rank][j]
    if u<cumulative or j==#profile.rows then return j end
  end
end
function M.draw(ticket)
  assert(ticket>=1 and ticket<=M.total and ticket==math.floor(ticket))
  local result=M.choose(M.profile(0.1,5),1,(ticket-0.5)/M.total)
  if result then return result-1 end
end
return M
