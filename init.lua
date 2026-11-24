-- practice: a switch next to the song list's Mirror one. on, a level never ends and nothing of it is kept: it opens
-- paused on a timeline to pick a section, where to play it from, a speed and whether it loops, and resuming plays the
-- section from there. a button in the replay player practises the mistakes nearest to where the replay is

local UE = CS.UnityEngine
local Input, Screen = UE.Input, UE.Screen
local kit = phigrospp.ui

local TAB = "Practice"
local enabled = setting("Practice mode", false, TAB)
local speed = setting("Practice speed", 1.0, { 0.25, 2, step = 0.05, unit = "×" }, TAB)
local loop = setting("Loop the section", true, TAB)
local lead = setting("Lead-in", 0.0, { 0, 3, step = 0.5, unit = " s" }, TAB)

local PREVIEW = 4 -- seconds of chart shown from a dragged end
local SHORTEST = 1 -- seconds a section lasts at least
local GAP, PAD = 2, 2 -- seconds: a replay's mistakes closer than GAP make one section, with PAD around them
local PLAYHEAD = { 1, 0.82, 0.3, 1 }
-- lucide's repeat and target
local REPEAT = [[<path d="m17 2 4 4-4 4" /><path d="M3 11v-1a4 4 0 0 1 4-4h14" /><path d="m7 22-4-4 4-4" />
  <path d="M21 13v1a4 4 0 0 1-4 4H3" />]]
local TARGET = [[<circle cx="12" cy="12" r="10" /><circle cx="12" cy="12" r="6" /><circle cx="12" cy="12" r="2" />]]
local GOOD, WRONG = { 0.63, 0.88, 1, 1 }, { 1, 0.36, 0.36, 1 } -- a replay's goods, its bads and misses

local sections = {} -- the section picked for each chart since the game started, by song id and difficulty
local mistakes = {} -- the marks of the replay each chart was last practised from, shown on its timeline
local once -- practising from a replay until back on the song list, whatever the switch says
local run, key -- the practice level (its components, chart, section and clock) and its chart's key in sections
local editor -- its timeline, rebuilt with each level

local function resetScore()
  local s = run.score
  s._score, s._percent, s._combo, s.maxcombo = 0, 0, 0, 0
  s.perfect, s.good, s.bad, s.miss, s.early, s.late = 0, 0, 0, 0, 0, 0
  s.isAllPerfect, s.isFullCombo = true, true
  s._noteCodes:Clear()
  if s.comboBlocked then s:UnblockCombo() end -- Petrichor's blocks lock the combo when touched
end

-- the section from the playhead (its start when none is given), with only its notes from there on, after the
-- lead-in of music picked. from its start the score is back at zero
local function begin(from)
  local progress, section = run.progress, run.section
  from = from or section.a
  phigrospp.jump(math.max(from - lead() * speed(), -progress._offset), section.b, from)
  if from == section.a then resetScore() end
  local blocks = run.judge.previewElementUpdateControl
  if blocks.HasBlocks then blocks:DestroyAndCreateAllBlocks() end -- the ones gone by come back
  phigrospp.speed(speed())
  run.begun = true
end

local function clock(t) return ("%d:%04.1f"):format(t // 60, t % 60) end


-- a knob sliding on a bar { x, y, width }: get() is where it is from 0 to 1, set(f) moves it, text() is written by
-- it, to the side its TextAnchor says. side puts it over the bar (1) or under it (-1), so two at the same place are
-- told apart, and timed is the time it's at in seconds, typed when its text is tapped
local function knob(e, bar, get, set, text, anchor, side, timed)
  local u, parent = e.u, e.go.transform
  side = side or 0
  local k = { bar = bar, get = get, set = set, text = text, anchor = anchor, side = side, timed = timed,
    image = kit.rect(parent, "practice-knob", { 0, bar.y + side * 16 * u }, { 8 * u, 48 * u }, { 1, 1, 1, 1 }, { 0.5, 0.5 }),
    label = kit.text(parent, "practice-label", e.font, { 0, bar.y + (side < 0 and -52 or 52) * u }, { 0, 0 }, 34 * u,
      anchor, { 0.5, 0.5 }) }
  e.knobs[#e.knobs + 1] = k
  return k
end

local function bar(e, x, y, width)
  kit.rect(e.go.transform, "practice-bar", { x, y }, { width, 8 * e.u }, { 1, 1, 1, 0.3 })
  return { x = x, y = y, width = width }
end

-- the section's ends on a timeline of the song, under it the speed and the loop switch
local function build()
  local u, width = Screen.height / 1080, Screen.width
  local e = { go = kit.overlay("practice", 32765), u = u, font = run.score.score.font, knobs = {}, reach = 60 * u }
  local parent = e.go.transform
  local song = bar(e, width * 0.2, 210 * u, width * 0.6)
  e.song = song
  e.fill = kit.rect(parent, "practice-section", { 0, song.y }, { 0, 8 * u }, { 1, 1, 1, 0.9 })
  for _, m in ipairs(mistakes[key] or {}) do
    kit.rect(parent, "practice-mistake", { song.x + song.width * m.t / run.length - u, song.y }, { 2 * u, 24 * u },
      m.judgement == "good" and GOOD or WRONG)
  end
  -- an end moved puts the playhead back at the section's start
  local function ends(which, limit, anchor)
    knob(e, song, function() return run.section[which] / run.length end, function(f)
      run.section[which] = limit(f * run.length)
      run.shown, run.at = run.section[which], run.section.a
    end, function() return clock(run.section[which]) end, anchor, 1, function() return run.section[which] end)
  end
  ends("a", function(t) return math.min(t, run.section.b - SHORTEST) end, 5) -- MiddleRight
  ends("b", function(t) return math.max(t, run.section.a + SHORTEST) end, 3) -- MiddleLeft
  -- the playhead, under the bar: where resuming plays from, inside the section
  knob(e, song, function() return run.at / run.length end, function(f)
    run.at = math.max(run.section.a, math.min(f * run.length, run.section.b - SHORTEST / 2))
    run.shown = run.at
  end, function() return clock(run.at) end, 4, -1, function() return run.at end).image.color = PLAYHEAD -- MiddleCenter
  local low, high, step = 0.25, 2, 0.05
  knob(e, bar(e, song.x, 90 * u, width * 0.25), function() return (speed() - low) / (high - low) end,
    function(f) speed(math.floor((low + f * (high - low)) / step + 0.5) * step) end,
    function() return ("%.2f×"):format(speed()) end, 4) -- MiddleCenter
  local size = 64 * u
  e.loop = kit.rect(parent, "practice-loop", { song.x + song.width - size, 90 * u }, { size, size }, { 1, 1, 1, 1 })
  e.loop.sprite = kit.icon(REPEAT)
  return e
end

local function draw(e)
  for _, k in ipairs(e.knobs) do
    local f = k.get()
    if f ~= k.at then
      k.at = f
      k.image.transform.anchoredPosition = { k.bar.x + k.bar.width * f, k.image.transform.anchoredPosition.y }
      k.label.transform.anchoredPosition = { k.bar.x + k.bar.width * f, k.label.transform.anchoredPosition.y }
      k.label.text = k.text()
    end
  end
  local a, b = e.knobs[1], e.knobs[2]
  e.fill.transform.anchoredPosition = { a.bar.x + a.bar.width * a.at, a.bar.y }
  e.fill.transform.sizeDelta = { a.bar.width * (b.at - a.at), 8 * e.u }
  e.loop.color = { 1, 1, 1, loop() and 1 or 0.3 }
end

-- whether a point is on a knob's text, which starts, is centred or ends at the knob as its TextAnchor says
local function written(e, k, x, y)
  local at, wide = k.label.transform.anchoredPosition, k.label.preferredWidth
  local left = at.x - wide * (k.anchor - 3) / 2
  return math.abs(y - at.y) < 30 * e.u and x > left - 16 * e.u and x < left + wide + 16 * e.u
end

-- a touch starting on a knob drags it, the nearest one when two are close: one over the bar is taken from above it,
-- one under it from below. a time tapped without moving is typed instead, in seconds: the system's number pad has
-- no colon
local function touch(e, t)
  local x, y, phase = t.m_Position.x, t.m_Position.y, t.m_Phase
  if t.m_FingerId == e.finger then
    local k, over = e.dragged, phase == 3 or phase == 4 -- Ended, Canceled
    if over then e.finger = nil end
    e.moved = e.moved or math.abs(x - e.x) > 12 * e.u
    if e.moved then return k.set(math.max(0, math.min(1, (x - k.bar.x) / k.bar.width))) end
    if over and e.tapped then
      e.typed = { knob = k, keyboard = UE.TouchScreenKeyboard.Open(("%.1f"):format(k.timed()), 2, false, false, false) } -- NumbersAndPunctuation
    end
    return
  end
  if phase ~= 0 or e.finger then return end -- Began
  local at = e.loop.transform.anchoredPosition
  if math.abs(x - at.x - 32 * e.u) < e.reach and math.abs(y - at.y) < e.reach then return loop(not loop()) end
  local nearest = e.reach
  for _, k in ipairs(e.knobs) do
    local away, up = math.abs(x - k.bar.x - k.bar.width * k.at), (y - k.bar.y) * (k.side == 0 and 1 or k.side)
    local reached = k.side == 0 and math.abs(up) < e.reach or up > -8 * e.u and up < e.reach
    local tapped = k.timed and written(e, k, x, y)
    if tapped or reached and away < nearest then
      nearest, e.finger, e.dragged, e.x, e.moved, e.tapped = tapped and 0 or away, t.m_FingerId, k, x, not tapped, tapped
    end
  end
end

-- the keyboard closed: what was typed is where the knob goes, when it's a time
local function typing(e)
  local keyboard = e.typed.keyboard
  if keyboard.status == 0 then return end -- Visible
  local t = keyboard.status == 1 and tonumber(keyboard.text) -- Done
  if t then e.typed.knob.set(math.max(0, math.min(1, t / run.length))) end
  e.typed = nil
end

-- the switch, by the song list's Mirror one
on("scene", function(name)
  if name ~= "SongSelector" then return end
  once = nil
  phigrospp.ui.switch("Practice", enabled, function() enabled(not enabled()) end)
end)

-- the mistakes of a replay closest to t as a section, the moment around t when it has none
local function nearest(marks, t)
  local best, away, cluster = { a = t, b = t }, math.huge, nil
  for _, m in ipairs(marks) do
    if not cluster or m.t - cluster.b > GAP then cluster = { a = m.t } end
    cluster.b = m.t
    local distance = math.max(cluster.a - t, t - cluster.b, 0)
    if distance < away then best, away = cluster, distance end
  end
  return { a = best.a - PAD, b = best.b + PAD }
end

-- in the replay player: the song starts again as a practice of what the replay got wrong around where it is
phigrospp.replay.button(TARGET, function()
  local chart, state, marks = playing(), phigrospp.replay.state(), phigrospp.replay.marks()
  local k = chart.id .. "." .. chart.difficulty
  sections[k], mistakes[k], once = nearest(marks, state.frames[math.max(state.cursor, 1)].t), marks, true
  phigrospp.replay.takeover()
end)

on("song", function(chart)
  if not (enabled() or once) or replaying() then return end
  local level = UE.Object.FindObjectOfType(CS.LevelControl)
  local progress = level.progressControl
  run = { progress = progress, judge = progress.judgeControl, score = progress.scoreControl }
  key = chart.id .. "." .. chart.difficulty
end)

on("leave", function() run = nil end)

-- a section paused goes on from there, one that ended or wasn't started from its start
on("pause", function()
  if not (run and run.begun) then return end
  local t, section = run.progress.nowTime, run.section
  run.at = t > section.a and t < section.b and t or section.a
end)

-- every resume plays the section from its playhead
on("resume", function()
  if run and run.length then begin(run.at) end
end)

-- a restart resumes the song too, then plays the section from its start
on("restart", function()
  if run and run.length then begin() end
end)

on("update", function()
  if not run then return end
  local progress = run.progress
  if not run.length then
    -- the level opens paused on its timeline, once the game knows how long the music is
    if progress._audioLength <= 0 then return end
    if progress._inChallengeMode then
      run = nil
      return
    end
    run.length = progress._audioLength - progress._offset - 0.25
    local section = sections[key] or { a = 0, b = run.length }
    section.a, section.b = math.max(section.a, 0), math.min(section.b, run.length) -- one from a replay can stick out
    sections[key], run.section = section, section
    progress.levelInformation.canLevelOver = false -- the game never ends the level, so nothing of it is saved
    phigrospp.counts(false)
    run.blur = phigrospp.find(progress.pauseBar.transform, "Translucent Image (1)").gameObject
    editor = build()
    progress:Play(false)
    run.shown, run.at = run.section.a, run.section.a
  end
  editor.go:SetActive(not progress.isPlaying)
  if progress.isPlaying then
    if run.begun and progress.nowTime >= run.section.b then
      if loop() then begin() else progress:Play(false) end
    end
    return
  end
  if editor.typed then
    typing(editor)
  else
    for i = 0, Input.touchCount - 1 do touch(editor, Input.GetTouch(i)) end
  end
  -- the pause menu blurs the chart, which shows while an end of the section is dragged
  run.blur:SetActive(not (editor.finger and editor.dragged.bar == editor.song))
  draw(editor)
  if run.shown then
    phigrospp.jump(run.shown, run.shown + PREVIEW)
    run.shown = nil
  end
end)
