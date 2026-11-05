# Menu bar widget system: progress note (round 3, 2026-11-05)

## Round 3 (component redesign): implemented
- Model (`Sources/App/App/MenuBar`): `DataField` (27 fields, label/format/level/history; free/remaining
  levels inverted = 1 - free/total, 0 when total is unknown), `FieldKind`, `FieldCategory`, `ByteUnit` + `ByteText`
  (auto/MB/GB, binary for memory), `ComponentVisual` (text, stacked2, iconValue, bar, hbar, ring, sparkline, dot; the single
  validity rule `supports(primary:secondary:)`), `ColorTarget`, `MenuBarComponent` (+`normalized()`, `isValid`),
  `MenuBarComponent+Legacy` (round-2 `MenuBarItemConfig` -> component, keeps id/colors/thresholds/enabled),
  `MenuBarConfig.components` (decodes legacy `items`, always encodes `components`), `ComponentLibrary` (40 entries), 8 presets
  (new: "Ayrıntılı"), store: add/remove/move/move(onto:)/resetToDefault.
- Rendering (`Sources/App/UI/StatusBar`): `ComponentRenderer` (widths only from widest samples), `MenuBarComposer`
  (components, `frames(of:)` for hit testing, bitmap/zoom kept), `MenuBarRenderKey` (line 2 text + histories),
  `WidgetPalette` (per-field color, colorTarget). StatusBarController logic unchanged except types.
- Settings: `MenuBarSettingsTab` = presets strip + "Varsayılana dön", clickable mock (`MenuBarEditorMock`, hit areas from
  composer frames, drag reorder, ←/→ via onMoveCommand, ⌫ via onDeleteCommand), `ComponentInspector`, `ComponentLibraryGrid`
  (category chips + `LibraryCard`, one click adds), layout options. Sidebar: "Görünüm galerisi" removed, "Hız sınırı" added.
- Obsolete files stubbed (comment only, safe to delete): WidgetRenderer, MenuBarItemEditor, MenuBarItemRow,
  WidgetStyleGallery, WidgetLegend, WidgetStyle+Options, PresetGalleryPane, MenuBarItemConfig+Color.
  Legacy model types (MenuBarItemConfig, MetricKind, WidgetStyle, NetworkDirection, NetworkValueSource) stay for decoding.
- Tests: MenuBarComponentTests (formatting, inversion, migration, library validity, width stability) + ported MenuBarConfigTests.

## Known issues / next
- Any failing XCTest assertion hangs the test host in XCTest symbolication (CoreSymbolication). Find it with `sample <pid>`.
- `TEST_RUNNER_ADALMON_PREVIEW_DIR=<dir>` works when set as a shell env prefix before `xcodebuild` (not as a build setting).
- GalleryCard, AdaptiveMenuBarMock and MenuBarMockPreview remain (MenuBarMockPreview is the actual-size strip).

## Round 4 (simple metric cards + compact layouts), 2026-11-05
- Default "Menü çubuğu" page is `MenuBarCardsTab` (+ `MenuBarCardsForm`, `MetricCardView`): one card per
  `MetricCardKind`, order = menu bar order (drag via `.onMove` + ↑/↓). "Gelişmiş düzenleyici…" opens the old
  `MenuBarSettingsTab` in `AdvancedMenuBarEditorSheet`.
- Cards are not stored: `MetricCardConfig` <-> components (`MetricCardConfig+Mapping`). Card components carry
  `MenuBarComponent.layout` (marker) and may use `tertiary` (3rd value). `cards(from:)` returns nil for lists the
  advanced editor changed -> notice "Gelişmiş düzende özelleştirildi" + "Basit düzene dön". Hidden card = disabled component.
- New visuals `oneLine`, `labelAbove`, `symbolStack` drawn by `CompactLayoutRenderer` (SF condensed, monospaced digits,
  new `WidgetText` roles; legacy roles unchanged). `MenuBarConfig.default` = `MetricCardConfig.defaults`.
- Threshold color of a mixed component (CPU % + °C) uses the field's own default thresholds for the other kind.
