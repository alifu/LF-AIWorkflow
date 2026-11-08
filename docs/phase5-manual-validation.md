# Phase 5 manual validation (notch UI)

Run a Debug build. Tick each item; the expected result is after the arrow.

## Displays
- [ ] Notched MacBook display: collapsed panel is invisible -> File/Edit menus and menu bar items either side of the notch stay clickable.
- [ ] Non-notched display, or Settings -> Displays "simulate no notch" / launch arg `-LFSimulateNotch` -> half-circle tab with mascot and count appears; expands correctly (width ~130 pt is known, TD-004).
- [ ] Notched Mac plus external display -> panel stays on the menu-bar screen.
- [ ] Unplug and replug the external display, rearrange displays, toggle "Displays have separate Spaces" -> panel repositions with no stray window.

## Windows and Spaces
- [ ] Full-screen app (Safari or Xcode): hover at the top -> panel appears; typing in the app still works while the panel is collapsed (no focus steal).
- [ ] Mission Control and swiping between Spaces -> panel is on every Space, is not listed as a window, and is not in Cmd-Tab.

## Hover and hotkey
- [ ] Pointer rests on the notch for 120 ms -> expands. Leaving for 300 ms -> collapses. Rapid in/out -> no flicker or stutter.
- [ ] Hotkey Option-Command-Space -> toggles open and closed without the mouse.
- [ ] Pin the panel -> stays open with the pointer away; unpin -> collapses after 300 ms.

## Composer
- [ ] Click the prompt and type -> text appears (non-activating panel still takes keys), panel stays open while focused. Command-Return starts the task.
- [ ] Pick a project, drag several files from Finder, use "Choose files..." -> chips appear; the limit text updates.
- [ ] Drop `.env` or a symlink pointing at `~/.ssh/id_rsa` -> secret warning; nothing is attached until confirmed.
- [ ] Switch to another tab and back -> documents and skill folders are still listed and still attach to the next task.
- [ ] Add a skill folder, quit, relaunch, choose the same project -> folder is remembered.

## Plan and review
- [ ] Plan ready -> peek bubble under the menu bar for ~7 s; clicking opens the approval view and the panel can still collapse later.
- [ ] Approve proceeds, Cancel cancels; "Open in editor" opens the plan; "View plan" shows on a done task and is hidden for a Code-start task.
- [ ] Review findings are sorted; clicking `src/File.swift:12` opens the file in the default app.
- [ ] A finding pointing at a `.command`, `.terminal`, `.app`, or an executable script inside the worktree -> only reveals in Finder; nothing launches.
- [ ] A finding pointing outside the worktree (`../..`, absolute, symlink escape) -> refused, nothing opens.

## Accessibility
- [ ] VoiceOver: collapsed item reads "N tasks running, <stage>"; tabs, rows, buttons are labelled; the peek is announced; opening a peek by VoiceOver leaves the panel able to auto-collapse later.
- [ ] Reduce Motion on -> fades instead of spring/scale.
- [ ] Light and Dark appearance -> all text readable.

## Known behavior
- [ ] Quit with a running task -> task state is lost (TD-028).
