function parseEmojis(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!Array.isArray(data)) return []
    for (var i = 0; i < data.length; i++) {
      var item = data[i]
      if (item && typeof item === "object")
        item._k = String(item.k || "").toLowerCase()
    }
    return data
  } catch (e) {
    return []
  }
}

function normalizedQuery(query) {
  return String(query || "").trim().toLowerCase()
}

function keywordText(item) {
  if (!item) return ""
  if (typeof item._k === "string") return item._k
  return String(item.k || "").toLowerCase()
}

function filterEmojis(emojis, query, limit) {
  var values = Array.isArray(emojis) ? emojis : []
  var needle = normalizedQuery(query)
  var max = limit === undefined || limit === null ? 1000 : Number(limit)
  if (isNaN(max)) max = 1000
  max = Math.max(0, max)
  if (max === 0) return []

  var out = []

  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    if (!item || !item.e) continue
    if (!needle || keywordText(item).indexOf(needle) >= 0) {
      out.push(item)
      if (out.length >= max) break
    }
  }

  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEmojis: parseEmojis,
    normalizedQuery: normalizedQuery,
    filterEmojis: filterEmojis
  }
}
