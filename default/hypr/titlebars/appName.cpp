#include "appName.hpp"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace fs = std::filesystem;

namespace {
  std::unordered_map<std::string, std::string> g_byWmClass;
  std::unordered_map<std::string, std::string> g_byLowerId;
  std::unordered_map<std::string, std::string> g_resolved;
  std::vector<fs::file_time_type>              g_stamps;
  std::chrono::steady_clock::time_point        g_lastCheck;
  bool                                         g_loaded = false;

  std::string lower(std::string text) {
    std::ranges::transform(text, text.begin(), [](unsigned char c) { return std::tolower(c); });
    return text;
  }

  std::vector<fs::path> applicationDirs() {
    std::vector<fs::path> dirs;

    const char* dataHome = std::getenv("XDG_DATA_HOME");
    const char* home     = std::getenv("HOME");
    if (dataHome && *dataHome)
      dirs.emplace_back(fs::path(dataHome) / "applications");
    else if (home && *home)
      dirs.emplace_back(fs::path(home) / ".local/share/applications");

    const char*       dataDirs = std::getenv("XDG_DATA_DIRS");
    const std::string list     = dataDirs && *dataDirs ? dataDirs : "/usr/local/share:/usr/share";
    size_t            start    = 0;
    while (start <= list.size()) {
      size_t end = list.find(':', start);
      if (end == std::string::npos)
        end = list.size();
      if (end > start)
        dirs.emplace_back(fs::path(list.substr(start, end - start)) / "applications");
      start = end + 1;
    }

    return dirs;
  }

  // Directory times move when an entry is added, removed or renamed, which is how
  // an installed web app reaches this cache without a Hyprland reload.
  std::vector<fs::file_time_type> stamps(const std::vector<fs::path>& dirs) {
    std::vector<fs::file_time_type> result;
    result.reserve(dirs.size());
    for (const auto& dir : dirs) {
      std::error_code ec;
      const auto      time = fs::last_write_time(dir, ec);
      result.push_back(ec ? fs::file_time_type::min() : time);
    }
    return result;
  }

  void readAndIndexEntry(const fs::path& path) {
    std::ifstream file(path);
    std::string   line, name, wmClass;
    bool          inEntry = false;

    while (std::getline(file, line)) {
      if (line.starts_with('[')) {
        if (inEntry)
          break;
        inEntry = line == "[Desktop Entry]";
        continue;
      }
      if (!inEntry)
        continue;
      if (name.empty() && line.starts_with("Name="))
        name = line.substr(5);
      else if (wmClass.empty() && line.starts_with("StartupWMClass="))
        wmClass = line.substr(15);
      if (!name.empty() && !wmClass.empty())
        break;
    }

    if (name.empty())
      return;

    if (!wmClass.empty())
      g_byWmClass.try_emplace(wmClass, name);
    g_byLowerId.try_emplace(lower(path.stem().string()), std::move(name));
  }

  void load(const std::vector<fs::path>& dirs) {
    g_byWmClass.clear();
    g_byLowerId.clear();
    g_resolved.clear();

    // Earlier directories win, so a user's own entry overrides the system one.
    std::unordered_set<std::string> seen;
    for (const auto& dir : dirs) {
      std::error_code ec;
      for (const auto& file : fs::directory_iterator(dir, ec)) {
        if (file.path().extension() != ".desktop" || !seen.insert(file.path().filename().string()).second)
          continue;
        readAndIndexEntry(file.path());
      }
    }
  }
}

std::string quattroAppName(const std::string& windowClass) {
  if (windowClass.empty())
    return "";

  const auto now = std::chrono::steady_clock::now();
  if (!g_loaded || now - g_lastCheck > std::chrono::seconds(2)) {
    g_lastCheck      = now;
    const auto dirs  = applicationDirs();
    auto       times = stamps(dirs);
    if (!g_loaded || times != g_stamps) {
      load(dirs);
      g_stamps = std::move(times);
      g_loaded = true;
    }
  }

  if (const auto cached = g_resolved.find(windowClass); cached != g_resolved.end())
    return cached->second;

  std::string name;
  if (const auto it = g_byWmClass.find(windowClass); it != g_byWmClass.end())
    name = it->second;
  else if (const auto it = g_byLowerId.find(lower(windowClass)); it != g_byLowerId.end())
    name = it->second;

  g_resolved.emplace(windowClass, name);
  return name;
}
