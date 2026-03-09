# Overlay Incremental Dictionaries Design

**Goal:** Make the translation popup render immediately after OCR selection, then update the primary translation and each dictionary section independently as their own async work completes.

## Problem

- The overlay currently switches to a single global loading state once a word is selected.
- Dictionary lookup is awaited as one batch, and the batch itself is executed source by source.
- The popup does not show partial progress, so one slow online provider delays the whole dictionary area.
- The primary translation and translated dictionary definitions are also blocked behind the full dictionary pass.

## Product Decision

- Keep the popup visible as soon as a word is selected.
- Remove the normal global "Translating" blocker for lookup results.
- Show loading indicators independently for:
  - the primary translation area
  - each enabled dictionary source section
- Preserve dictionary display order according to settings, regardless of actual return order.
- A single provider failure should affect only its own section.

## Recommended Architecture

### 1. Incremental Overlay Model

Replace the current "final content only" overlay payload with a partial-result model that can be updated repeatedly:

- word and phonetic stay at the top level
- primary translation becomes its own stateful section
- dictionary sections become a fixed ordered list, one section per enabled source

Each section carries a presentation state:

- `loading`
- `ready`
- `empty`
- `failed`

### 2. AppModel-Owned Orchestration

Keep orchestration inside `AppModel`.

- `AppModel` builds the initial partial overlay as soon as OCR finds a word.
- `AppModel` launches async work for the primary translation and for each dictionary source in parallel.
- Every subtask checks the active `lookupID` before mutating state.

This keeps cancellation, stale-result protection, and UI updates in one place.

### 3. Single-Source Dictionary API

Expose a `lookupSingle` style API from `DictionaryService` rather than extending it into a stream abstraction.

- Local and online lookups can share one entry point.
- `AppModel` can fan out over enabled sources with `TaskGroup`.
- Existing `lookupAll` can be retained for compatibility, but the popup should stop depending on it.

### 4. Section-Level Post-Processing

Each dictionary task is responsible for producing display-ready content:

- pretranslated online entries can be published directly
- same-language mode can normalize definitions immediately
- cross-language local entries can run definition translation within that source task

That avoids one provider waiting on another provider's definition translation.

### 5. View Rendering

`OverlayView` should render one stable popup shell:

- header
- primary translation block
- dictionary sections in configured order

For sections that are still pending, render a compact inline spinner instead of hiding the section.

## Data Flow

1. User presses the shortcut and OCR resolves the token under cursor.
2. `AppModel` creates a partial overlay with the selected word, placeholder primary translation state, and one placeholder section per enabled dictionary source.
3. The overlay is shown immediately.
4. `AppModel` starts the primary translation task.
5. `AppModel` starts one dictionary task per enabled source in parallel.
6. As each task finishes, `AppModel` updates only the affected section.
7. If the active lookup changes, stale tasks stop updating the overlay.

## Error Handling

- OCR / capture failures keep existing behavior.
- Missing system translation language pack should not block pretranslated online dictionary sections from showing.
- A dictionary provider timeout or parsing failure marks only that section as failed or empty.
- If all sections fail and no primary translation is available, fall back to the existing error path.

## Testing Strategy

- Build and test the app target and existing unit tests.
- Add unit coverage for the ordering and placeholder creation logic if practical.
- Manual verification:
  - popup appears immediately after word selection
  - one fast provider appears before a slower provider
  - section order remains stable
  - releasing the hotkey cancels pending updates
  - moving to a new word does not mix results from the old lookup

## Risks

- `AppModel.swift` will gain more state-handling code unless a later refactor extracts a lookup session object.
- More frequent overlay updates may reveal animation or resizing issues in the popup.
- Online providers with very different latency can cause visible reflow unless the section layout is kept compact and stable.
