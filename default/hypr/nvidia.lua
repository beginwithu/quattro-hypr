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

local function file_readable(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local nvidia_egl_icd = "/usr/share/glvnd/egl_vendor.d/10_nvidia.json"
local has_nvidia_egl_icd = file_readable(nvidia_egl_icd)

if mode == "gsp-display" then
  hl.env("NVD_BACKEND", "direct")
  hl.env("LIBVA_DRIVER_NAME", "nvidia")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
  if has_nvidia_egl_icd then
    hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", nvidia_egl_icd)
  end
elseif mode == "gsp-hybrid" then
  hl.env("NVD_BACKEND", "direct")
elseif mode == "legacy-display" then
  hl.env("NVD_BACKEND", "egl")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
  if has_nvidia_egl_icd then
    hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", nvidia_egl_icd)
  end
elseif mode == "legacy-hybrid" then
  hl.env("NVD_BACKEND", "egl")
end
