local paths = require("default.hypr.paths")

local nvidia = paths.quattro_path .. "/bin/quattro-hw-nvidia"

-- Read cached sysfs IDs in a single pass rather than shelling out to lspci or
-- spawning 4 separate subshells during Hyprland's 1.5s config reload budget.
local pipe = io.popen(o.shell_quote(nvidia) .. " --mode 2>/dev/null")
local mode = "none"
if pipe then
  mode = (pipe:read("*l") or "none"):gsub("%s+$", "")
  pipe:close()
end

if mode == "gsp-display" then
  hl.env("NVD_BACKEND", "direct")
  hl.env("LIBVA_DRIVER_NAME", "nvidia")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
elseif mode == "gsp-hybrid" then
  hl.env("NVD_BACKEND", "direct")
elseif mode == "legacy-display" then
  hl.env("NVD_BACKEND", "egl")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
elseif mode == "legacy-hybrid" then
  hl.env("NVD_BACKEND", "egl")
end
