#define WLR_USE_UNSTABLE

#include <unistd.h>

#include <any>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/shared/parserUtils/ParserUtils.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleEffectContainer.hpp>
#include <hyprland/src/config/lua/bindings/LuaBindingsInternal.hpp>
#include <hyprland/src/config/lua/types/LuaConfigColor.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <hyprutils/string/VarList.hpp>

#include <algorithm>

#include "barDeco.hpp"
#include "globals.hpp"

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

// Do NOT change this function.
APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

static void onNewWindow(PHLWINDOW window) {
  if (std::ranges::any_of(window->presentation().decorations(), [](const auto &d) { return d->getDisplayName() == "Hyprbar"; }))
    return;

  auto bar = makeShared<CQuattroFloatingHyprBar>(window);
  g_pQuattroFloatingGlobalState->bars.emplace_back(bar);
  bar->m_self = bar;
  HyprlandAPI::addWindowDecoration(QUATTRO_FLOATING_PHANDLE, window, std::move(bar));
}

static void onPreConfigReload() {
  g_pQuattroFloatingGlobalState->buttons.clear();
}

static void onConfigReloaded() {
  for (auto &b : g_pQuattroFloatingGlobalState->bars) {
    if (!b)
      continue;

    b->onConfigReloaded();
  }
}

static void onUpdateWindowRules(PHLWINDOW window) {
  const auto BARIT = std::find_if(g_pQuattroFloatingGlobalState->bars.begin(), g_pQuattroFloatingGlobalState->bars.end(),
                                  [window](const auto &bar) { return bar && bar->getOwner() == window; });

  if (BARIT == g_pQuattroFloatingGlobalState->bars.end())
    return;

  if (const auto BAR = BARIT->lock()) {
    BAR->updateRules();
    window->updateWindowData();
  }
}

int newQuattroFloatingLuaButton(lua_State *L) {
  if (!lua_istable(L, 1))
    return Config::Lua::Bindings::Internal::configError(L, "add_button: expected a table { bg_color, fg_color, size, icon, action }");

  SQuattroFloatingHyprButton button;

  {
    Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

    lua_getfield(L, 1, "bg_color");

    Config::Lua::CLuaConfigColor parser(0);
    auto err = parser.parse(L);
    if (err.errorCode != Config::Lua::PARSE_ERROR_OK)
      return Config::Lua::Bindings::Internal::configError(L, "add_button: failed to parse bg_color");

    button.bgcol = parser.parsed();
  }

  {
    Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

    lua_getfield(L, 1, "fg_color");

    Config::Lua::CLuaConfigColor parser(0);
    auto err = parser.parse(L);
    if (err.errorCode != Config::Lua::PARSE_ERROR_OK)
      return Config::Lua::Bindings::Internal::configError(L, "add_button: failed to parse fg_color");

    button.userfg = true;
    button.fgcol = parser.parsed();
  }

  {
    Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

    lua_getfield(L, 1, "size");

    if (!lua_isnumber(L, -1))
      return Config::Lua::Bindings::Internal::configError(L, "add_button: size must be an integer");

    button.size = lua_tointeger(L, -1);
  }

  {
    Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

    lua_getfield(L, 1, "icon");

    if (!lua_isstring(L, -1))
      return Config::Lua::Bindings::Internal::configError(L, "add_button: icon must be a string");

    button.icon = lua_tostring(L, -1);
  }

  {
    Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

    lua_getfield(L, 1, "action");

    if (!lua_isstring(L, -1))
      return Config::Lua::Bindings::Internal::configError(L, "add_button: action must be a string");

    button.cmd = lua_tostring(L, -1);
  }

  g_pQuattroFloatingGlobalState->buttons.push_back(std::move(button));

  for (auto &b : g_pQuattroFloatingGlobalState->bars) {
    if (!b)
      continue;

    b->m_bButtonsDirty = true;
  }

  return 0;
}

static PLUGIN_DESCRIPTION_INFO initializeQuattroFloating(HANDLE handle) {
  QUATTRO_FLOATING_PHANDLE = handle;

  const std::string HASH = __hyprland_api_get_hash();
  const std::string CLIENT_HASH = __hyprland_api_get_client_hash();

  if (HASH != CLIENT_HASH) {
    HyprlandAPI::addNotification(QUATTRO_FLOATING_PHANDLE,
                                 "[hyprbars] Failure in initialization: Version mismatch (headers ver is not equal to running hyprland ver)",
                                 CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
    throw std::runtime_error("[hb] Version mismatch");
  }

  g_pQuattroFloatingGlobalState = makeUnique<SQuattroFloatingGlobalState>();
  g_pQuattroFloatingGlobalState->nobarRuleIdx = Desktop::Rule::windowEffects()->registerEffect("hyprbars:no_bar");
  g_pQuattroFloatingGlobalState->barColorRuleIdx = Desktop::Rule::windowEffects()->registerEffect("hyprbars:bar_color");
  g_pQuattroFloatingGlobalState->titleColorRuleIdx = Desktop::Rule::windowEffects()->registerEffect("hyprbars:title_color");

  g_pQuattroFloatingGlobalState->windowOpenListener = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { onNewWindow(w); });
  g_pQuattroFloatingGlobalState->windowUpdateRulesListener = Event::bus()->m_events.window.updateRules.listen([](PHLWINDOW w) { onUpdateWindowRules(w); });

  g_pQuattroFloatingGlobalState->config.barColor = makeShared<Config::Values::CColorValue>("plugin:hyprbars:bar_color", "Change the bar color", 0x88333333);
  g_pQuattroFloatingGlobalState->config.textColor = makeShared<Config::Values::CColorValue>("plugin:hyprbars:col.text", "Change the text color", 0xffffffff);
  g_pQuattroFloatingGlobalState->config.inactiveBarColor =
      makeShared<Config::Values::CColorValue>("plugin:hyprbars:bar_color_inactive", "Inactive title bar color; transparent means use bar_color", 0x00000000);
  g_pQuattroFloatingGlobalState->config.inactiveButtonColor = makeShared<Config::Values::CColorValue>(
      "plugin:hyprbars:inactive_button_color", "Change the inactive button's color. 0x00000000 means unset", 0x00000000);
  g_pQuattroFloatingGlobalState->config.barHeight = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_height", "Change the bar's height", 15);
  g_pQuattroFloatingGlobalState->config.barTextSize = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_text_size", "Change the bar's text size", 10);
  g_pQuattroFloatingGlobalState->config.barTextWeight =
      makeShared<Config::Values::CFontWeightValue>("plugin:hyprbars:bar_text_weight", "Bar's title text weight (e.g. \"bold\" or an integer 100-1000)", 400);
  g_pQuattroFloatingGlobalState->config.barTitleEnabled =
      makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_title_enabled", "Whether to enable titles in the bar", true);
  g_pQuattroFloatingGlobalState->config.barBlur =
      makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_blur", "Whether to enable blur of the bar", false);
  g_pQuattroFloatingGlobalState->config.barTextFont = makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_text_font", "Bar's text font", "Sans");
  g_pQuattroFloatingGlobalState->config.barTextAlign =
      makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_text_align", "Bar's text alignment", "center");
  g_pQuattroFloatingGlobalState->config.barPartOfWindow =
      makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_part_of_window", "Whether the bar is a part of the window (reserves space)", true);
  g_pQuattroFloatingGlobalState->config.barPrecedenceOverBorder =
      makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_precedence_over_border", "Whether the bar is before, or after the border", false);
  g_pQuattroFloatingGlobalState->config.barButtonsAlignment =
      makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_buttons_alignment", "Alignment of the bar buttons", "right");
  g_pQuattroFloatingGlobalState->config.barPadding = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_padding", "Padding of the bar", 7);
  g_pQuattroFloatingGlobalState->config.barButtonPadding =
      makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_button_padding", "Padding of the bar buttons", 5);
  g_pQuattroFloatingGlobalState->config.buttonRounding =
      makeShared<Config::Values::CIntValue>("plugin:hyprbars:button_rounding", "Button corner radius. -1 preserves the upstream circular style", -1);
  g_pQuattroFloatingGlobalState->config.buttonBorderSize =
      makeShared<Config::Values::CIntValue>("plugin:hyprbars:button_border_size", "Width of the button border", 0);
  g_pQuattroFloatingGlobalState->config.buttonBorderColor =
      makeShared<Config::Values::CColorValue>("plugin:hyprbars:button_border_color", "Color of the button border", 0x00000000);
  g_pQuattroFloatingGlobalState->config.enabled = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:enabled", "Whether bars are enabled", false);
  g_pQuattroFloatingGlobalState->config.iconOnHover =
      makeShared<Config::Values::CBoolValue>("plugin:hyprbars:icon_on_hover", "Whether to use an icon on hover of the buttons", false);
  g_pQuattroFloatingGlobalState->config.onDoubleClick =
      makeShared<Config::Values::CStringValue>("plugin:hyprbars:on_double_click", "Action to execute on double click of the bar", "");
  g_pQuattroFloatingGlobalState->config.workspaceTag =
      makeShared<Config::Values::CStringValue>("plugin:hyprbars:workspace_tag", "Restrict bars to windows with this tag", "");

  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barColor);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.textColor);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.inactiveBarColor);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.inactiveButtonColor);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barHeight);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barTextSize);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barTextWeight);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barTitleEnabled);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barBlur);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barTextFont);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barTextAlign);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barPartOfWindow);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barPrecedenceOverBorder);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barButtonsAlignment);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barPadding);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.barButtonPadding);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.buttonRounding);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.buttonBorderSize);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.buttonBorderColor);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.enabled);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.workspaceTag);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.iconOnHover);
  HyprlandAPI::addConfigValueV2(QUATTRO_FLOATING_PHANDLE, g_pQuattroFloatingGlobalState->config.onDoubleClick);

  HyprlandAPI::addLuaFunction(QUATTRO_FLOATING_PHANDLE, "hyprbars", "add_button", ::newQuattroFloatingLuaButton);
  g_pQuattroFloatingGlobalState->configPreReloadListener = Event::bus()->m_events.config.preReload.listen([] { onPreConfigReload(); });
  g_pQuattroFloatingGlobalState->configReloadedListener = Event::bus()->m_events.config.reloaded.listen([] { onConfigReloaded(); });

  // add deco to existing windows
  for (auto &w : Desktop::windowState()->windows()) {
    if (w->isHidden() || !validMapped(w))
      continue;

    onNewWindow(w);
  }

  HyprlandAPI::reloadConfig();

  return {"hyprbars", "A plugin to add title bars to windows.", "Vaxry", "1.0"};
}

static void exitQuattroFloating() {
  if (g_pQuattroFloatingGlobalState) {
    g_pQuattroFloatingGlobalState->windowOpenListener.reset();
    g_pQuattroFloatingGlobalState->windowUpdateRulesListener.reset();
    g_pQuattroFloatingGlobalState->configPreReloadListener.reset();
    g_pQuattroFloatingGlobalState->configReloadedListener.reset();
  }

  for (auto &m : State::monitorState()->monitors())
    m->m_scheduledRecalc = true;

  g_pHyprRenderer->context().m_pass.removeAllOfType("CQuattroFloatingBarPassElement");

  if (g_pQuattroFloatingGlobalState) {
    Desktop::Rule::windowEffects()->unregisterEffect(g_pQuattroFloatingGlobalState->barColorRuleIdx);
    Desktop::Rule::windowEffects()->unregisterEffect(g_pQuattroFloatingGlobalState->titleColorRuleIdx);
    Desktop::Rule::windowEffects()->unregisterEffect(g_pQuattroFloatingGlobalState->nobarRuleIdx);
  }
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) { return initializeQuattroFloating(handle); }
APICALL EXPORT void PLUGIN_EXIT() { exitQuattroFloating(); }
