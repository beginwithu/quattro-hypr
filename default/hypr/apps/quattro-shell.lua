-- Window and layer rules for the Quattro Quickshell surfaces. The
-- shell-wide bar / menu / popouts are layer-shell.

-- Keep the bar instant: no layer-shell fade/slide animation.
hl.layer_rule({ match = { namespace = "quattro-bar" }, no_anim = true, animation = "none" })

-- Launcher, image selector, emojis, clipboard overlays, the OSD, reminders, the
-- Wi-Fi QR code and keyboard-driven panels should pop without compositor layer
-- animations. Overlays open as soon as their scale is ready, without a
-- compositor fade or slide. Panels keep their own QML opacity transition
-- for normal open/close, and skip it for panel handoff.
hl.layer_rule({ match = { namespace = "^(quattro-menu|quattro-image-selector|quattro-emojis|quattro-clipboard|quattro-keyboard-panel|quattro-osd|quattro-reminders|quattro-network-qr|quattro-dock|quattro-dock-apps|quattro-share-picker|quattro-video-cut|org\\.quattro\\.screensaver)$" }, no_anim = true, animation = "none" })

-- The background layer handles its own transitions; disable compositor fades.
hl.layer_rule({ match = { namespace = "^quattro-background$" }, no_anim = true, animation = "none" })
