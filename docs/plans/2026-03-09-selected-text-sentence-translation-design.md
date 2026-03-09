# Selected Text Sentence Translation Design

**Goal:** When the user presses the existing shortcut, the app should translate the current text selection as a sentence if the pointer is inside the selected region; otherwise it should keep the current OCR word lookup behavior.

## Problem

- The current lookup entry in `AppModel` always starts from screen capture and OCR, so it can only resolve a token under the pointer.
- The app has no way to read the host app's selected text, selected range, or selection bounds.
- The current "dictionary source" model mixes true dictionaries with translation providers, which makes the sentence use case harder to route cleanly.
- The overlay is optimized for word results and has no sentence-specific presentation path.

## Product Decisions

### Scope

- Reuse the existing shortcut. No new hotkey is introduced.
- Sentence translation is triggered only when both conditions are true:
  - the focused app exposes a non-empty selected text
  - the current pointer is inside the selected text region
- If selected text cannot be read, no bounds can be resolved, or accessibility permission is unavailable, the app falls back to the existing OCR word lookup path.

### User Experience

- Users keep the current gesture: press the shortcut near text.
- If the pointer is inside a valid selection, the popup shows sentence translation for the selected text.
- If the pointer is not inside a selection, the popup behaves exactly as it does today for word lookup.
- Continuous translation remains available only for OCR word mode. Sentence mode is frozen for the current key press.

### Non-Goals

- Adding a second shortcut for sentence translation.
- Building full sentence history, multi-paragraph translation, or document translation.
- Providing dictionary definitions for sentence mode.
- Reworking all settings UI in the same change beyond what is required to separate service categories.

## Current-State Constraints

### Lookup Flow

- `AppModel.performLookup` currently assumes every lookup begins with screen recording, OCR, token hit-testing, then word-oriented translation and dictionary fan-out.
- `DictionaryService.normalizeWord` trims input to the first token, so it is intentionally unsuitable for sentence text.

### Permissions

- `PermissionManager` tracks only screen recording.
- Reading selected text from other apps on macOS requires Accessibility permission and AX APIs.

### Service Model

- `TranslationBridge` already handles the popup's primary translation and is a better fit for sentence translation than the dictionary stack.
- `DictionarySource.SourceType` currently includes `google` and `deepl`, even though they are translation products, while `bing` and `youdao` are presented as dictionaries.

## Recommended Architecture

### 1. Selection-First Lookup Routing

Introduce a request-scoped lookup intent before OCR starts:

- `.sentenceSelection(selectedText, selectionBounds)`
- `.ocrWord(mouseLocation)`

Routing rules:

1. On hotkey trigger, ask a new `SelectedTextService` for the current focused element's selection snapshot.
2. If the snapshot contains text and the pointer is inside the resolved bounds, use sentence mode.
3. Otherwise, fall back to the existing OCR word pipeline.

This keeps the current word behavior intact and avoids invasive changes to OCR.

### 2. New SelectedTextService

Add a dedicated service responsible for Accessibility reads:

- fetch the focused UI element
- read `kAXSelectedTextAttribute`
- read `kAXSelectedTextRangeAttribute`
- resolve bounds with `kAXBoundsForRangeParameterizedAttribute`
- normalize bounds into a screen-space `CGRect`

The service should return a compact snapshot model:

- selected text
- selected range
- selection bounds in screen coordinates
- source app identifier when available

The service should fail quietly and let the caller fall back to OCR.

### 3. Permission Model Extension

Extend `PermissionManager` with Accessibility permission state and actions:

- `accessibility: Bool` in `PermissionStatus`
- `requestAccessibility()`
- `openAccessibilitySettings()`

The app must not block word lookup if Accessibility permission is missing. The permission is additive: required for sentence mode, optional for OCR mode.

### 4. Split Lookup Execution Paths

Refactor `AppModel.performLookup` into two explicit branches:

- `performSentenceSelectionLookup`
- `performOcrWordLookup`

Shared responsibilities stay in `AppModel`:

- hotkey lifecycle
- lookup cancellation
- stale result protection with `activeLookupID`
- overlay updates

Sentence branch behavior:

- skip screen capture and OCR
- skip pronunciation
- skip dictionary section fan-out
- call translation service with the full selected text

Word branch behavior:

- preserve current OCR, pronunciation, dictionary, and continuous translation behavior

### 5. Service Classification

Replace the current implicit provider behavior with explicit capability categories.

#### Dictionary Services

Used only for word lookup:

- `system`
- `ecdict`
- `wordNet`
- `bing`
- `youdao`

These providers return dictionary-style content or short word translations that fit the existing dictionary section UI.

#### Translation Services

Used only for sentence lookup:

- `system translation` (`TranslationBridge`)
- `google`
- `deepl`

The architecture should expose this as a separate `TranslationService` abstraction even if v1 only wires `TranslationBridge` in the UI flow.

### 6. Settings Migration

The current `dictionarySources` setting should stop carrying sentence translators.

Recommended migration:

- keep `system`, `ecdict`, `wordNet`, `bing`, and `youdao` inside `dictionarySources`
- move `google` and `deepl` into a new sentence-translation configuration
- default the sentence translation provider to the existing system translation service

This keeps the configuration model aligned with actual runtime behavior.

### 7. Overlay Presentation Modes

The overlay needs a sentence-aware presentation path.

Recommended model:

- word mode: current header, phonetic, primary translation, dictionary sections
- sentence mode: original text + translated text, with copy actions and no phonetic or dictionary sections

Sentence mode should allow a wider popup and multi-line wrapping without reusing word-specific labels.

## Data Flow

1. User presses the existing shortcut.
2. `AppModel` asks `SelectedTextService` for the focused selection snapshot.
3. If the pointer is inside a valid selection bounds, `AppModel` starts sentence mode.
4. Sentence mode shows a lightweight loading popup and requests full-text translation.
5. If selection mode is not available, `AppModel` falls back to the current OCR word mode.
6. On shortcut release, both modes cancel and dismiss through the existing hotkey lifecycle.

## Error Handling

- Missing Accessibility permission: fall back to OCR word lookup.
- Focused app exposes selected text but not bounds: fall back to OCR word lookup.
- Selected text is empty or whitespace: fall back to OCR word lookup.
- Sentence translation fails: show a sentence-mode error state in the popup.
- Word lookup continues to preserve current error behavior.

## Testing Strategy

### Automated

- Add unit tests for lookup routing decisions:
  - valid selection + pointer inside bounds -> sentence mode
  - valid selection + pointer outside bounds -> OCR mode
  - missing accessibility data -> OCR mode
- Add settings migration tests for splitting `dictionarySources` and translation settings.
- Add lightweight view/model tests if sentence presentation state is extracted into testable models.

### Manual

- TextEdit: select a sentence, keep the pointer inside the selection, press the shortcut, confirm sentence translation appears.
- TextEdit: same selection with pointer outside the selection, confirm OCR word lookup still runs.
- Safari and Chrome: verify fallback works when selection bounds support differs.
- Xcode or Electron app: verify missing AX data does not break OCR lookup.
- Hold the shortcut on selected text and move the mouse: confirm sentence mode does not continuously retrigger.

## Risks

- AX selection bounds support differs across host apps, so fallback behavior must be deterministic.
- Sandboxed macOS behavior may differ between development and distribution for cross-app AX reads, so real-app verification is required.
- Splitting provider categories without migration can silently change user preferences, so migration logic must be explicit and tested.
- Sentence text can be much longer than word text, which may reveal overlay sizing issues.

## Recommended Rollout

### Phase 1

- Add `SelectedTextService`
- add Accessibility permission support
- add lookup routing and sentence-mode overlay
- keep sentence translation backed by the existing system translation bridge

### Phase 2

- add dedicated sentence translation provider settings if needed
- migrate `google` and `deepl` fully out of dictionary settings UI
- refine app-specific selection bounds fallbacks based on manual testing

## Success Criteria

- Pressing the current shortcut inside a selected text region translates the selected sentence.
- Pressing the same shortcut outside the selected region preserves current OCR word lookup behavior.
- Word mode uses only dictionary services.
- Sentence mode uses only translation services.
- Missing Accessibility permission never breaks the existing OCR workflow.
