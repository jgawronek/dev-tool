# Journey Map Reference

## Contents
- Tool Selection Journey
- Favorites Journey
- Search Journey
- Empty / Error States
- DO/DON'T Pairs

---

## Tool Selection Journey

**Intent:** User wants to switch to a different tool quickly.
**Preconditions:** App is open, sidebar visible, `ToolState.selectedToolId` initialized from `shared_preferences`.

```
Sidebar visible
  → User clicks _SidebarItem (lib/ui/sidebar.dart:126)
  → onTap fires → widget.onSelect(tool.id)
  → state.selectedToolId.value = id (lib/ui/main_shell.dart:54)
  → ValueListenableBuilder rebuilds content area
  → selectedTool.builder(context) renders new tool panel
```

**Success state:** Tool panel renders immediately; sidebar item shows selection dot + bold weight.
**Failure state:** `selectedTool == null` (e.g., search active + no match) → "No tools match your search." message.
**Recovery:** User clears search via `×` button → full tool list restores → prior selection reactivates.

---

## Favorites Journey

**Intent:** Pin frequently used tools for faster access.
**Preconditions:** At least one tool loaded in registry.

```
User views tool in content area
  → Clicks star icon (_ToolHeader, lib/ui/main_shell.dart:132)
  → state.toggleFavorite(tool.id) called
  → favorites ValueNotifier updates
  → shared_preferences persists the new set
  → Sidebar "Favorites" section re-renders
```

**Success state:** Tool appears at top of sidebar under "Favorites"; star icon fills.
**Failure state:** No failure path — toggle is purely local.
**Edge case:** Favorites section shows "No favorites yet." (sidebar.dart:97) when set is empty — do not hide the section header.

---

## Search Journey

**Intent:** Filter tools by name when registry grows large.
**Preconditions:** `_searchController` initialized from `widget.searchQuery` (sidebar.dart:31-32).

```
User types in search field (sidebar.dart:65-86)
  → onChanged fires widget.onSearch(value)
  → state.searchQuery.value updates
  → ValueListenableBuilder in MainShell rebuilds with filtered list
  → If filtered empty → content area shows empty-state message
```

**Success state:** Matching tools show instantly; non-matching tools disappear from sidebar.
**Failure state:** No matches → empty-state message in content area (main_shell.dart:73).
**Recovery:** User presses `×` suffix button or clears field → full list restores.

---

## DO / DON'T Pairs

**DO** auto-select `filtered.first` when active tool is filtered out (already implemented at main_shell.dart:39-44).  
**DON'T** silently leave `selectedToolId` pointing to a non-visible tool — users lose context.

**DO** preserve `_searchController.text` in sync with `widget.searchQuery` via `didUpdateWidget` (sidebar.dart:35-41).  
**DON'T** let the text field and the state notifier drift — the `×` button will stop working correctly.

**DO** show the "Favorites" section header even when the list is empty (sidebar.dart:93-99).  
**DON'T** hide the section — it teaches discoverability on first use.

**DO** select a tool immediately on tap with no confirmation step.  
**DON'T** add hover-delay reveals or multi-click selection — this is a tool launcher, not a nav menu.