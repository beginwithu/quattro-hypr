-- Captive portal sign-in: a small floating window that
-- quattro-network-captive-portal closes once the internet is reachable.
local captive_portal = "^.+-ping\\.archlinux\\.org__.*$"
o.window(captive_portal, { tag = "-chromium-based-browser" })
o.window(captive_portal, { float = true, center = true, size = { 900, 760 } })
