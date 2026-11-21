-- practice: a switch next to the song list's Mirror one. on, a level never ends and nothing of it is kept: it opens
-- paused on a timeline to pick a section, a speed and whether it loops, and resuming plays that section from its start

local UE = CS.UnityEngine
local Input, Screen, Time = UE.Input, UE.Screen, UE.Time
local kit = phigrospp.ui

local TAB = "Practice"
local enabled = setting("Practice mode", false, TAB)
local speed = setting("Practice speed", 1.0, { 0.25, 2, step = 0.05, unit = "×" }, TAB)
local loop = setting("Loop the section", true, TAB)

local LEAD = 2 -- seconds of music played before the section, at the speed picked
local PREVIEW = 4 -- seconds of chart shown from a dragged end
local SHORTEST = 1 -- seconds a section lasts at least
local REPEAT = [[<path d="m17 2 4 4-4 4" /><path d="M3 11v-1a4 4 0 0 1 4-4h14" /><path d="m7 22-4-4 4-4" />
  <path d="M21 13v1a4 4 0 0 1-4 4H3" />]] -- lucide's repeat

local sections = {} -- the section picked for each chart since the game started, by song id and difficulty
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

-- the section from LEAD seconds of music before its start, with only its notes and a score of zero
local function begin()
  local progress, section = run.progress, run.section
  local from = math.max(section.a - LEAD * speed(), -progress._offset, 0)
  phigrospp.jump(from, section.b)
  resetScore()
  local blocks = run.judge.previewElementUpdateControl
  if blocks.HasBlocks then blocks:DestroyAndCreateAllBlocks() end -- the ones gone by come back
  run.clock, run.music.audioSource.pitch = from + progress._offset, speed()
end

-- the game's time is the music's, read from a clock that doesn't follow its pitch: ours is given instead before the
-- game reads it. AudioSource.time follows the pitch but moves a buffer at a time, so ours runs by itself, pulled to it
local function tick(progress)
  local music = run.music
  if not run.clock or not progress.isPlaying or music.CurrentStatus ~= 0 then return end
  local source = music.audioSource
  local clock, heard = run.clock + Time.deltaTime * source.pitch, source.time
  run.clock = math.abs(heard - clock) > 0.12 and heard or clock + (heard - clock) * 0.05
  music.time = run.clock
end

local function clock(t) return ("%d:%04.1f"):format(t // 60, t % 60) end

-- a knob sliding on a bar { x, y, width }: get() is where it is from 0 to 1, set(f) moves it, text() is written over
-- it, to the side its TextAnchor says
local function knob(e, bar, get, set, text, anchor)
  local u, parent = e.u, e.go.transform
  e.knobs[#e.knobs + 1] = { bar = bar, get = get, set = set, text = text,
    image = kit.rect(parent, "practice-knob", { 0, bar.y }, { 8 * u, 48 * u }, { 1, 1, 1, 1 }, { 0.5, 0.5 }),
    label = kit.text(parent, "practice-label", e.font, { 0, bar.y + 52 * u }, { 0, 0 }, 34 * u, anchor, { 0.5, 0.5 }) }
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
  local function ends(which, limit, anchor)
    knob(e, song, function() return run.section[which] / run.length end, function(f)
      run.section[which] = limit(f * run.length)
      run.shown = run.section[which]
    end, function() return clock(run.section[which]) end, anchor)
  end
  ends("a", function(t) return math.min(t, run.section.b - SHORTEST) end, 5) -- MiddleRight
  ends("b", function(t) return math.max(t, run.section.a + SHORTEST) end, 3) -- MiddleLeft
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
      k.image.transform.anchoredPosition = { k.bar.x + k.bar.width * f, k.bar.y }
      k.label.transform.anchoredPosition = { k.bar.x + k.bar.width * f, k.bar.y + 52 * e.u }
      k.label.text = k.text()
    end
  end
  local a, b = e.knobs[1], e.knobs[2]
  e.fill.transform.anchoredPosition = { a.bar.x + a.bar.width * a.at, a.bar.y }
  e.fill.transform.sizeDelta = { a.bar.width * (b.at - a.at), 8 * e.u }
  e.loop.color = { 1, 1, 1, loop() and 1 or 0.3 }
end

-- a touch starting on a knob drags it, the nearest one when two are close
local function touch(e, t)
  local x, y, phase = t.m_Position.x, t.m_Position.y, t.m_Phase
  if t.m_FingerId == e.finger then
    if phase == 3 or phase == 4 then e.finger = nil end -- Ended, Canceled
    local k = e.dragged
    return k.set(math.max(0, math.min(1, (x - k.bar.x) / k.bar.width)))
  end
  if phase ~= 0 or e.finger then return end -- Began
  local at = e.loop.transform.anchoredPosition
  if math.abs(x - at.x - 32 * e.u) < e.reach and math.abs(y - at.y) < e.reach then return loop(not loop()) end
  local nearest = e.reach
  for _, k in ipairs(e.knobs) do
    local away = math.abs(x - k.bar.x - k.bar.width * k.at)
    if math.abs(y - k.bar.y) < e.reach and away < nearest then nearest, e.finger, e.dragged = away, t.m_FingerId, k end
  end
end

-- the switch: a copy of the Mirror one on its right, moving and hiding with it, coloured like it is on and off
on("scene", function(name)
  if name ~= "SongSelector" then return end
  local mirror = UE.Object.FindObjectOfType(CS.SongSelector).mirrorTextSize.transform
  local switch = UE.Object.Instantiate(mirror.gameObject, mirror.parent, false).transform
  switch.name = "practice-switch"
  switch:SetParent(mirror, false)
  switch.anchorMin, switch.anchorMax, switch.pivot, switch.anchoredPosition = { 1, 0.5 }, { 1, 0.5 }, { 0, 0.5 }, { 92, 0 }
  local back, text = phigrospp.find(switch, "Button"), phigrospp.find(switch, "Text"):GetComponent(UE.UI.Text)
  switch:GetComponent(UE.UI.Text).text, text.text = "Practice", "Practice"
  local function paint()
    back:GetComponent(CS.Lean.Gui.LeanPolygon).color = enabled() and { 1, 1, 1, 0.75 } or { 0, 0, 0, 0.5 }
    text.color = enabled() and { 0, 0, 0, 1 } or { 1, 1, 1, 0.7 }
  end
  local button = back:GetComponent(UE.UI.Button)
  button.onClick = UE.UI.Button.ButtonClickedEvent()
  phigrospp.click(button, function()
    enabled(not enabled())
    paint()
  end)
  paint()
end)

on("song", function(chart)
  if not enabled() or replaying() then return end
  local level = UE.Object.FindObjectOfType(CS.LevelControl)
  local progress = level.progressControl
  run = { progress = progress, judge = progress.judgeControl, score = progress.scoreControl, music = progress.audioSource }
  key = chart.id .. "." .. chart.difficulty
  progress.levelInformation.canLevelOver = false -- the game never ends the level, so nothing of it is saved
  run.hook = hook(CS.ProgressControl, "Update", { before = tick })
end)

on("leave", function()
  if not run then return end
  unhook(run.hook)
  run = nil
end)

-- every resume plays the section from its start
on("resume", function()
  if run and run.length then begin() end
end)

on("update", function()
  if not run then return end
  local progress = run.progress
  if not run.length then
    -- the level opens paused on its timeline, once the game knows how long the music is
    if progress._audioLength <= 0 then return end
    if progress._inChallengeMode then
      unhook(run.hook)
      run = nil
      return
    end
    run.length = progress._audioLength - progress._offset - 0.25
    sections[key] = sections[key] or { a = 0, b = run.length }
    run.section = sections[key]
    phigrospp.counts(false)
    run.blur = phigrospp.find(progress.pauseBar.transform, "Translucent Image (1)").gameObject
    editor = build()
    progress:Play(false)
    run.shown = run.section.a
  end
  editor.go:SetActive(not progress.isPlaying)
  if progress.isPlaying then
    if run.clock and progress.nowTime >= run.section.b then
      if loop() then begin() else progress:Play(false) end
    end
    return
  end
  for i = 0, Input.touchCount - 1 do touch(editor, Input.GetTouch(i)) end
  -- the pause menu blurs the chart, which shows while an end of the section is dragged
  run.blur:SetActive(not (editor.finger and editor.dragged.bar == editor.song))
  draw(editor)
  if run.shown then
    phigrospp.jump(run.shown, run.shown + PREVIEW)
    run.shown = nil
  end
end)
