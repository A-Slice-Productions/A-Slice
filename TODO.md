# TODO - Fix Chart Editor Notes Not Appearing in PlayState

## Root Cause
`PlayState.loaded` is a static flag that remains `true` when entering the chart editor mid-play (via debug key). When pressing Enter to playtest, `generateSong()` sees `loaded == true` and skips reloading newly charted notes from `SONG.notes`, using stale `unspawnNotes` from memory instead.

## Steps
- [x] Analyze the task and understand the bug
- [x] Investigate ChartingState.goToPlayState() flow
- [x] Investigate PlayState.generateSong() loaded flag logic
- [x] Get user approval on the fix plan
- [x] Edit `source/states/editors/ChartingState.hx` to reset `PlayState.loaded = false` and clear `PlayState.unspawnNotes` in `goToPlayState()`
- [x] Verify the change compiles / confirm result

