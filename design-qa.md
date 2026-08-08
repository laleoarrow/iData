# iData landing page — design QA

**Source visual truth**

- `/Users/leoarrow/.codex/generated_images/019fb5a3-a6c8-7a03-a937-f45c9e2f0a1c/exec-3071271a-693a-46bf-bba3-d49fe52e3ddb.png`
- Source pixels: `944 × 1666` PNG. The generated concept has no browser CSS viewport or DPR metadata.

**Rendered implementation**

- Local route: `http://127.0.0.1:4173/`
- Desktop screenshot: `/tmp/idata-page-desktop-reset.png`
- Desktop viewport: `1280 × 720` CSS px; browser DPR `2`; full-page capture exported at CSS density as `1280 × 2217` px.
- Responsive evidence: `/tmp/idata-page-mobile-final.png` at `390 × 844` CSS px, plus a measured tablet geometry pass at `820 × 1000` CSS px.
- State: dark theme, English product UI, latest GitHub release resolved to `v0.2.20`, default page state.

**Normalization**

- The source and implementation full-page images were each normalized to `720` px width.
- Source became `720 × 1271`; implementation became `720 × 1247` and was padded to `720 × 1271` with the page background.
- Side-by-side full comparison: `/tmp/idata-design-qa-final-full.png` (`1440 × 1271`, source left, implementation right).
- Focus comparison: `/tmp/idata-design-qa-final-focus.png` (`1440 × 900`, source left, implementation right), covering the header, hero, install command, product image, and annotation rail.

**Findings**

- No actionable P0, P1, or P2 mismatch remains.
- Fonts and typography: Inter and IBM Plex Mono reproduce the reference's editorial sans/technical mono hierarchy. The final headline keeps the intended two-line desktop composition, with controlled wrapping on smaller screens.
- Spacing and layout rhythm: the final page preserves the reference's restrained header, large hero, stacked install actions, dominant product image, narrow annotation rail, two-column release block, and minimal footer. Border radii, rules, and spacing remain deliberately restrained.
- Colors and visual tokens: near-black surfaces, cool white text, muted gray secondary text, blue actions, and fine gray dividers map cleanly to the source. Contrast remains readable without glass or decorative effects.
- Image quality and asset fidelity: the implementation intentionally replaces the concept's generated product rendering with the real iData v0.2.20 app screenshot in English, as requested. The crop is sharp, fills the intended frame, and has no transparency halo or fake UI asset.
- Copy and content: product claims are concise and grounded in the repository: native macOS shell, real VisiData workflow, compressed-file support, macOS requirement, current release, and Homebrew command.
- Icons: one consistent Phosphor icon family is used for visible controls; the product logo and interface are real assets rather than CSS or SVG approximations.
- Responsiveness: measured horizontal overflow is `0 px` at 1280, 820, and 390 CSS px. Product, annotation, release, and footer grids collapse without clipped controls or awkward overlap.
- Accessibility: the page declares English, includes semantic navigation and headings, descriptive product-image alt text, a skip link, visible keyboard focus, practical mobile targets, and reduced-motion handling.

**Open Questions**

- None blocking. The header label is `Guide` instead of the concept's `Docs` because the destination is the repository README; this is an intentional content correction.

**Comparison History**

1. Pass 1 (`/tmp/idata-page-desktop-pass1.png`)
   - P2: the second headline line wrapped to two lines, changing the reference's above-the-fold composition.
   - P2: the real product screenshot retained too much outer padding, making the core product surface feel smaller than the reference.
   - Fixes: removed the desktop headline width constraint, preserved the second line at desktop widths, and tightened the real screenshot crop with an explicit aspect ratio plus measured scale/translation.
   - Post-fix evidence: `/tmp/idata-page-desktop-pass3.png` shows the two-line headline and a substantially larger, better-integrated product image.
2. Pass 2 (`/tmp/idata-page-desktop-pass3.png`)
   - P2: the download CTA and Homebrew command sat side by side, while the selected reference uses a clearer vertical install hierarchy.
   - Fix: grouped download/compatibility and Homebrew label/command separately, then stacked both groups in `.hero-tools`.
   - Post-fix evidence: `/tmp/idata-page-desktop-reset.png`, `/tmp/idata-design-qa-final-full.png`, and `/tmp/idata-design-qa-final-focus.png` show the corrected hierarchy with no new P0/P1/P2 issue.
3. Production pass (`https://laleoarrow.github.io/iData/`)
   - P2: the external Phosphor stylesheet loaded without a browser warning but did not expose its glyph rules on GitHub Pages, leaving the visible icon boxes at `0 × 0`.
   - Fix: self-hosted the pinned Phosphor 2.1.1 regular WOFF2 asset and limited the local glyph map to the five icons used by the page.
   - Post-fix evidence: `/tmp/idata-icon-fix-local.png` and `/tmp/idata-live-deployed-icon-fixed.png` show the icon set rendered from the local `Phosphor` font with no console error.

**Primary Interactions Tested**

- Latest GitHub release metadata resolves to `v0.2.20` and the primary download link resolves to the direct universal DMG asset.
- Homebrew copy buttons enter the copied state and show the `Homebrew command copied` live-status toast.
- Header, guide, GitHub, release-note, and download link destinations were inspected.
- Keyboard focus reaches the header links and renders the defined blue focus outline.
- Desktop, tablet, and mobile breakpoint geometry was measured; mobile and desktop were visually captured.

**Console Errors Checked**

- Final local browser pass: no warnings or errors. The production pass also verifies the self-hosted icon font after deployment.

**Implementation Checklist**

- [x] Use the selected black editorial design direction.
- [x] Replace generated product UI with a real English iData screenshot.
- [x] Preserve a two-line desktop headline and stacked install hierarchy.
- [x] Bind release metadata and DMG URL to the GitHub release API with a static fallback.
- [x] Serve the pinned icon font locally so production rendering does not depend on a third-party stylesheet.
- [x] Verify responsive layout, focus styling, copy feedback, and console output.

**Follow-up Polish**

- No blocking polish remains. A future release could replace the static screenshot when the app's visible onboarding UI changes.

final result: passed
