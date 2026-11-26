function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function entrySubtext(entry) {
  return String((entry && entry.genericName) || "")
}

function entrySortKey(entry) {
  return entryName(entry).toLowerCase()
}

function keywordText(entry) {
  try {
    if (entry && entry.keywords && typeof entry.keywords.join === "function") return entry.keywords.join(" ")
  } catch (e) {
  }
  return ""
}

function entrySearchText(entry) {
  if (!entry) return ""
  return [entry.name, entry.genericName, entry.comment, keywordText(entry), entry.id].join(" ").toLowerCase()
}

function wordText(value) {
  return String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
}

function words(value) {
  var values = wordText(value).split(/[^a-z0-9]+/)
  var result = []
  for (var i = 0; i < values.length; i++) {
    if (values[i]) result.push(values[i])
  }
  return result
}

function entryAcronym(entry) {
  var values = words([entry && entry.name, entry && entry.genericName, keywordText(entry), entry && entry.id].join(" "))
  var result = ""
  for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
  return result
}

function splitTerms(queryLower) {
  if (!queryLower) return []
  var raw = queryLower.split(/\s+/)
  var out = []
  for (var i = 0; i < raw.length; i++) {
    if (raw[i]) out.push(raw[i])
  }
  return out
}

function scoreEntry(entry, nameLower, q, terms) {
  if (!q) return 0

  var idLower = null
  var haystack = null
  var acronym = null

  for (var i = 0; i < terms.length; i++) {
    var term = terms[i]
    if (nameLower.indexOf(term) >= 0) continue
    if (idLower === null) idLower = String((entry && entry.id) || "").toLowerCase()
    if (idLower.indexOf(term) >= 0) continue
    if (haystack === null) haystack = entrySearchText(entry)
    if (haystack.indexOf(term) >= 0) continue
    if (term.length <= 5) {
      if (acronym === null) acronym = entryAcronym(entry)
      if (acronym.indexOf(term) >= 0) continue
    }
    return -1
  }

  if (idLower === null) idLower = String((entry && entry.id) || "").toLowerCase()
  var directName = nameLower.indexOf(q)
  var directId = idLower.indexOf(q)
  if (directName === 0) return 10000 - nameLower.length
  if (directId === 0) return 9500 - idLower.length
  if (directName > 0) return 8000 - directName * 10 - nameLower.length
  if (directId > 0) return 7600 - directId * 10 - idLower.length

  if (haystack === null) haystack = entrySearchText(entry)
  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return 6000 - hayIndex

  if (acronym === null) acronym = entryAcronym(entry)
  var acronymIndex = acronym.indexOf(q)
  if (acronymIndex === 0) return 5000 - acronym.length
  if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acronym.length

  return 4000 - nameLower.length
}

function fuzzyScore(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0
  return scoreEntry(entry, entryName(entry).toLowerCase(), q, splitTerms(q))
}

function sortedEntries(values, query, hiddenCallback) {
  var q = String(query || "").trim().toLowerCase()
  var terms = splitTerms(q)
  var rows = []

  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || entry.noDisplay) continue
    if (hiddenCallback && hiddenCallback(entry)) continue
    var name = entryName(entry)
    if (!name) continue
    var nameLower = name.toLowerCase()
    var score = q ? scoreEntry(entry, nameLower, q, terms) : 0
    if (score < 0) continue
    rows.push({ entry: entry, score: score, key: nameLower, name: nameLower })
  }

  rows.sort(function(a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.key < b.key) return -1
    if (a.key > b.key) return 1
    if (a.name < b.name) return -1
    if (a.name > b.name) return 1
    return 0
  })

  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    entryName: entryName,
    entrySubtext: entrySubtext,
    entrySortKey: entrySortKey,
    entrySearchText: entrySearchText,
    entryAcronym: entryAcronym,
    fuzzyScore: fuzzyScore,
    sortedEntries: sortedEntries
  }
}
