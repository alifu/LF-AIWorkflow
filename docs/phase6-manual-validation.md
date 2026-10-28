# Phase 6 manual validation

Run the app from Xcode (Debug). Force the display with the launch argument `-LFSimulateNotch YES` (notched) or `NO` (no notch). Change macOS appearance in System Settings > Appearance, or use Settings > General > Appearance.

## 1. Style matrix
Repeat for {Classic, Pop Art} x {Light, Dark} x {notched, no notch}.

| Check | Expected |
|---|---|
| Collapsed wings | Black in every cell; mascot and count legible on them |
| Expanded panel | Classic: plain, no outline or shadow. Pop Art: 2.5 pt black outline, hard 4 pt shadow, halftone dots on the paper |
| Pop Art edges | Outline and hard shadow are fully visible at all panel edges (not clipped); no-notch half circle outline not clipped (width is TD-004) |
| Stage chips | All five stages readable. Classic Dark: BLACK text on bright fills. Classic Light: fills are darker than before. This is the intentional contrast fix (TD-061); judge the look |
| Peek | Classic: single line. Pop Art: comic bubble whose tail points at the mascot |
| Celebration | Pop Art: DONE! or OOPS! burst for about 1.2 s. Classic: checkmark fade |
| Other screens | Terminal tab, Plan, Review, Composer and approval sheet are legible; progress bar visible |

## 2. Settings
| Check | Expected |
|---|---|
| General > art style | Picker preview updates live as you choose; choice survives relaunch |
| Appearance override | Light or Dark applies to the panel AND the Settings window; System follows macOS |
| Hotkey presets | Picking another preset works without relaunch; the old one stops working |
| Refused shortcut | A shortcut the system refuses shows the "already in use" message, and the previous shortcut still works |
| Esc / click-outside | Both collapse the panel (not while pinned or while composing text) |
| Peek on/off | Off: no bubble on task events; on: bubble appears |
| Tools tab | Path override accepted for an executable; Test button shows the version; a non-executable file is rejected with a message; Re-detect works |
| Stages / Budgets | Out-of-range turns or tokens are clamped with a note; bad model name rejected |
| Per-day cap | The "Per day" field is shown disabled, caption "Daily cap isn't enforced yet" (TD-066) |
| New tasks only | Change a model or budget while a task runs: the running task keeps its old values; the next new task uses the new ones |

## 3. Accessibility
| Setting | Expected |
|---|---|
| Reduce Motion | Mascot is static; the burst appears without animation; panel uses a simple transition |
| Reduce Transparency | No halftone dots; plain paper color |
| VoiceOver | Each chip reads "<Stage> <status>"; buttons and Settings controls have labels; the style preview is described; the disabled Per-day field is read as unavailable and not enforced; peek is announced; mascot is not read |
| Keyboard only | Cmd-, opens Settings; Tab reaches every control |

## 4. Regression (Classic)
Hover expand, pin, composer, plan approval and review still behave as in `docs/phase5-manual-validation.md`.
