# Chinese Localization Polish Design

## Goal

Improve the quality of the Simplified Chinese copy across the native `iData` app shell and `README_zh.md` so the product reads like a native macOS app instead of a direct translation.

## Scope

This pass covers:

- user-visible Chinese copy in `Sources/iData/*.swift`
- affected Chinese assertions in `Tests/iDataAppTests/*`
- the full Chinese documentation in `README_zh.md`

This pass does not cover:

- localization architecture changes such as moving strings into `.xcstrings`
- English copy rewrites unless a paired bilingual string must stay structurally aligned
- behavioral changes to app flows, settings, tutorial logic, or file handling

## Approved Direction

Use a `macOS native` Chinese voice:

1. short, direct UI labels
2. restrained system-style helper text
3. stable terminology across welcome, sidebar, settings, help, tutorial, and errors
4. minimal marketing tone and minimal spoken-language filler

## Copy Principles

### UI labels

- Prefer concise system verbs such as `打开`, `显示`, `移除`, `恢复`, `检查更新`.
- Avoid stacked near-synonyms such as `清除所有最近文件记录` when `清除最近项目` or equivalent shorter wording is sufficient.
- Keep control labels parallel across similar actions.

### Descriptions and helper text

- Prefer one clear sentence over explanatory or persuasive phrasing.
- Avoid translation-shaped structures such as `你可以…`, `只需…`, `快速了解…` unless the sentence becomes unclear without them.
- Preserve technical accuracy without sounding like documentation pasted into the UI.

### Errors and status

- State the problem first, then the recovery action if needed.
- Prefer system-style wording such as `无法…`, `未找到…`, `请先…`.
- Remove colloquial or overly chatty phrases from error paths.

### Documentation

- Keep `README_zh.md` aligned with the product voice: direct, professional, and readable.
- Preserve installation and release accuracy while removing unnatural wording and overlong sentences.

## Terminology Baseline

- `Preferences` -> `偏好设置`
- `Settings` in generic UI affordances -> `设置`
- `Recent Files` -> context-dependent `最近项目` or `最近文件`, favor whichever matches the surrounding UI density
- `Default app` -> `默认应用`
- `Session` -> `会话` where already established in the app
- `Show in Finder` -> `在 Finder 中显示`
- `One-Click Setup` -> `一键配置` unless the surrounding context explicitly requires `安装`

Existing product names and technical names such as `iData`, `VisiData`, `Finder`, `Excel`, `JSON Lines`, and file suffixes remain untranslated unless the current UI already uses an accepted Chinese form.

## Work Breakdown

### 1. Native app shell

Prioritize the strings users see most often:

1. toolbar and sidebar controls
2. welcome view summaries and empty states
3. preferences sections and explanatory text
4. launch, routing, and dependency errors
5. tutorial and help copy

### 2. Documentation

Rewrite `README_zh.md` for the same tone, especially:

1. product introduction
2. install and dependency guidance
3. release and development sections

### 3. Tests

Update only the assertions that intentionally validate Chinese wording. Keep the tests checking meaning, not brittle full-sentence duplication, unless exact text is required by behavior.

## Risks And Controls

- The copy is currently distributed inline across multiple Swift files, so broad edits can unintentionally break tests that assert fragments.
- Some phrases appear in both UI and tests with different acceptable wording. Prefer updating tests to assert the revised stable terms instead of preserving awkward copy.
- Terminology can drift between `ContentView`, `PreferencesView`, and `AppModel` if the pass is not done holistically; this is why the whole Chinese surface is included in one pass.

## Verification

After implementation:

1. run `swift test`
2. run a macOS `xcodebuild` build
3. spot-check the highest-traffic Chinese surfaces in source for terminology consistency

## Non-Goals

- No new features
- No restructuring of localization storage
- No expansion to additional languages
