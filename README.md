# Practice

A mod for [Phigros++](https://github.com/ggmolly/PhigrosPlusPlus) that adds a Practice switch next to the song list's Mirror one. With it on, a song opens paused on a timeline: drag the two ends of the section to practise, pick a speed from 0.25× to 2× and whether the section loops, then resume. The section plays from two seconds before its start every time, with the score and the counts back at zero, and the song never ends, so nothing of it is saved: no record, no replay, nothing sent to phigros.tools.

## Install

Open the **Mods** tab of the game's settings and pick Practice in the catalog, or open [this link](phigrospp://install/ggmolly/phigrospp-practice) on the device.

## Settings

| Setting | |
|---|---|
| Practice mode | The same switch as the one on the song list |
| Practice speed | From 0.25× to 2×, the music's pitch follows it |
| Loop the section | Off, the song pauses at the section's end |

The speed and the loop are also on the timeline, which shows whenever the song is paused. Dragging an end of the section shows the chart there.

## How it works

The game makes every note when a level starts and destroys each one once it's judged. To start a section, the mod asks Phigros++ to put the song two seconds before it (`phigrospp.jump`), which destroys the notes left, has the game make the ones up to the section's end again and moves the music, then it sets the score back to zero. The game's time comes from a clock that ignores the music's pitch, so at other speeds the mod gives it where the music really is.

The level is told it can't end and that it doesn't count (`phigrospp.counts`), so it isn't recorded and the game never reaches the result screen, where it saves a play. Challenge mode and replays play as usual.

It needs a Phigros++ newer than 0.3.0-beta.1, for `phigrospp.jump` and `phigrospp.counts`. On iOS it needs JIT, its hooks aren't written into the IPA.
