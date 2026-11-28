# Changelog

## 1.6.2

Resource Tracker 1.6.2 requires PrettyUI 1.4.0

- Resource Tracker 1.6.2 opens in the native Plugin Hub by default.
- Turn on Use PrettyUI Side Bar to switch to PrettyUI’s panel. In Classic layout, open it from the PrettyUI sidebar. In Modern layout, open it from the PrettyUI ribbon.
- In Modern layout, unlock your game interface and drag the tracker by its title bar onto a compatible window header or tab strip to dock it. PrettyUI remembers the panel’s placement.
- The Resource Tracker icon appears on the docked tab, PrettyUI ribbon, and Classic sidebar.
- In PrettyUI mode, open Settings from the cog next to Session. In Plugin Hub mode, open Settings from the cog in the bottom-right corner.
- Switch between the two views in Classic Mode Settings or Plugin Hub, depending on your game layout. Hover over the info icon for an explanation. The view preference is saved per character.
- Hide Plugin Hub ribbon is available when the tracker is displayed in the Plugin Hub. It is greyed out while the PrettyUI panel is active.

## 1.6.1

Tracker panel and settings
- Updated to use PrettyUI 1.3.3+ automatic components.
- Added a ribbon icon to the resources folder.
- Added Setting: Under Plugin Hub, enable "Hide Plugin Hub ribbon" to give the tracker more room while its page is open. The option is off by default, is saved per character.
- The tracker, Session window, Settings window, and item editor now use PrettyUI’s automatic component IDs. This resolves the legacy allocation warning when opening tracker controls.
- Compact tooltips build on first hover and retain their styling on repeat hovers.
- The Session and Settings windows can be moved in Classic layout and while the game interface is locked.
- Category tabs remember their scroll position when the tracker is resized. If you widen the panel enough to show every tab, narrowing it again restores your previous position.
- If you hide every skill tab, a reminder appears to re-enable a tab in Settings.

Recent items overlay
- Overlay rows now supports 1–10 rows, with 7 by default.
- With Show goals enabled, overlay items with a goal show their progress toward the target.
- The Backdrop opacity slider ranges from 0% to 100%, with 25% as the default. Turn on Show overlay backdrop to use it.

Saved Profiles
- Saved Profiles opens on Current, which now displays the active character.
- The recovery action is now called Copy Profile. Selecting another profile lets you copy its counts, goals, settings, and history into your active save. The button is disabled when Current is selected.
- Delete Profile removes the selected profile after confirmation. Deleting Current resets the tracker data for the active character.
- The profile controls use a more compact layout. Confirmation buttons highlight in red so you can see which action is armed.

Session and daily history
- Export Session, below New session, exports the current session as CSV.
- Export Day, below Clear history, exports the date selected in the Daily History dropdown.
- Both exports include resource counts, active gathering time in seconds, and items per hour. Click the CSV field, then press Ctrl+A and Ctrl+C to copy it.

## 1.6.0

- Added Player Owned Ports tracking. 
- The ANCHOR tab groups Ports Resources, Trade Goods, and Ship Rewards.
- 'Ports Resource' and 'Trade Good' stock updates without opening the Ports panel. 
- Added tracked PoP items: Gemstone kaseki and Tengu tsuba 
- Added Current Balances: Opening a Ports resource or trade good shows its Owned amount below the controls, with (MAX) at its cap. 
- Invention materials also show their current Owned amount.
- Unified row controls: A shared item editor provides goals and reset controls across tabs. 
- Ports rows omit manual count, pin, and remove actions.
- Added an optional gain sign. Positive gains show a green + beside count in rows. 
- Show green + on gains is enabled by default and can be turned off in Settings.
- Polished the tracker UI: Updated tab and toolbar icons, spacing, tooltips, and expanded row borders.
- Bank presets: Preset withdrawals are now excluded from resource gains. This covers presets loaded from the bank window and through Load Last Preset.
- Added an optional transparent overlay for recent tracker items. Choose 4–10 rows (default 7) and Shift+drag to save its position for your character.
- Added a 25% dark backdrop option for the overlay, off by default.
