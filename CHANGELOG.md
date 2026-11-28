# Changelog

## 1.6.3



## 1.6.2

### Changes

- Resource Tracker requires PrettyUI 1.4.0 or later and opens in the native Plugin Hub by default.
- Open Settings with the tools icon next to Session in the PrettyUI panel or in the bottom-right corner of the Plugin Hub.
- **Hide Plugin Hub ribbon** gives the tracker more room while its Hub page is open. The option is off by default, is saved per character, and is disabled in PrettyUI mode.

### Additions

- Turn on **Use PrettyUI Side Bar** to use the PrettyUI floating panel. The view you choose is saved per character.
- Open the panel from the sidebar in Classic layout or the ribbon in Modern layout. You can also select **Open docked tracker** on the tracker’s Plugin Hub page while PrettyUI sidebar mode is active.
- The Resource Tracker icon appears on the docked tab, PrettyUI ribbon, and Classic sidebar.
- To dock the tracker in Modern layout, unlock the game interface and drag the panel by its title bar onto a compatible window header or tab strip. PrettyUI remembers its placement.

### Fixes

- Fixed a logout error that could occur if Resource Tracker tried to refresh its windows after the game interface closed.

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

## 1.5.1

- Replaced the ALL text tab with a backpack icon.
- Its hover text now reads "All Items", the Spirits tab now reads "Seren Spirits".
- Enlarged the All and skill tab icons slightly.
- Replaced the custom Reset Count and Remove Resource images with PrettyUI refresh and bin icons. Both retain their two-click confirmation and red highlight.
- Updated the ribbon toggle to show a gold eye when the ribbon is visible and a gray eye when hidden. 
- Known limitation: Ribbon visibility still resets when the Plugin Hub rebuilds during resizing.

## 1.5.0

- Made trackingAccess optional. chatAccess remains required. Saves prefer the tracking ID and use a linked character name when tracking permission is unavailable.
- Added 'Saved Profiles' recovery. Players can find local saves and copy it to their current character’s profile.
- Added 'Delete all data' for Resource Tracker’s records and characters.
- Fixed a UI component ID limit.

## 1.4.0

- Added a settings button to Resource Tracker’s footer
- Added a standalone Resource Tracker settings window, replacing the plugin’s settings entry in Plugin Hub’s Manage page
- Updated tooltips for the footer buttons, tabs, long item names, and item controls with smaller text and cleaner positioning

## 1.3.0

- Fixed issue on rebuilding the plugin panel on resize.
- Added a toggle button to the Button_Layer of the plugin hub to [hide/show] the plugin ribbon icons.

## 1.2.0

- Long resource names now show in a hover tooltip instead of scrolling.
- Fixed a UI ID limit error that could prevent the tracker panel from opening.
- Removed some unused fields.

## 1.1.4

- Added Splintering arrow tips to Woodcutting tracking.
- Added Deathspore arrow tips to Mining tracking.
- Added sedimentary, igneous, and metamorphic geodes to Mining tracking.
- Added Pylon battery and Rex skeleton fragments to Archaeology tracking.
- Added Show Artefacts to hide artefact rows without deleting counts.
- Added two-click clearing for individual skill tabs while retaining session and daily history.

## 1.1.3

- Added 'New session' button to start a new session any time from the 'This Session' window.
- Added clearer rate information on the session window.
- Improved window resizing and goal row spacing
- Updated the pin icon.
- Replaced cycling group filters with a dropdown, ordered Archaeology sites by level, and moved “Other” and “Rare finds” to the end.
- Added Tetracompass pieces and Complete tomes to the Archaeology catalog.

## 1.1.2

- Added background to session window.
- Added missing items from the Seren Spirit gifts catalog
- Changed filters for woodcutting

## 1.1.1

- Fixed a row render error when closing the plugin hub window
- Added a 'Pin to top' option for item rows
- Added information icons on the sessions window

## 1.1.0

- Moved session and daily history into a window opened from a new tab.
- Tab tooltips were improved.
- 'All' tab disappears when only one skill tab is enabled.

## 1.0.1

- Fixed Boon of Crondis and metal-bank reward counting.
- Added wood-box gains without double-counting transfers.
- Updated resource IDs and item icons.
- Fixed daily history selection and improved panel layout.

## 1.0.0

- initial release