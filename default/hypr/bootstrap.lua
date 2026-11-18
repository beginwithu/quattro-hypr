-- Hyprland bootstrap for Quattro's Lua module path.

local home = os.getenv("HOME")
local reload_prefixes = {
  "default.hypr",
  "hypr",
  "quattro.current.theme",
}

local function should_reload_module(module)
  for _, prefix in ipairs(reload_prefixes) do
    if module == prefix or module:sub(1, #prefix + 1) == prefix .. "." then
      return true
    end
  end

  return false
end

local modules_to_reload = {}
for module in pairs(package.loaded) do
  if should_reload_module(module) then
    table.insert(modules_to_reload, module)
  end
end

for _, module in ipairs(modules_to_reload) do
  package.loaded[module] = nil
end

local function resolve_quattro_path()
  local env_path = os.getenv("QUATTRO_PATH")
  if env_path and env_path ~= "" then
    return env_path
  end

  local user_path = (home or "") .. "/.local/share/quattro"
  local f = io.open(user_path .. "/default/hypr/quattro.lua", "r")
  if f then
    f:close()
    return user_path
  end

  return "/usr/share/quattro"
end

-- Load generated state from XDG_STATE_HOME, user modules from XDG_CONFIG_HOME,
-- and Quattro defaults from $QUATTRO_PATH.
local state_home = os.getenv("XDG_STATE_HOME")
if not state_home or state_home == "" then
  state_home = (home or "") .. "/.local/state"
end

local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then
  config_home = (home or "") .. "/.config"
end

package.path = state_home
  .. "/?.lua;"
  .. config_home
  .. "/?.lua;"
  .. resolve_quattro_path()
  .. "/?.lua;"
  .. package.path
