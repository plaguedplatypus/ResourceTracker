# Changelog

## 1.6.1

- Updated the Plugin Hub tracker to use PrettyUI 1.3.0 component allocation. PrettyUI 1.3.0 or later is required.
- Open Session and Settings on the dedicated plugin layer. Explicitly use automatic IDs for PrettyUI controls across the tracker, including the item editor.
- Compact tooltips now build on first hover and retain their styling on repeat hovers.
- The Session and Settings windows can be moved and resized in Classic layout and while the game interface is locked.
- Added a **Backdrop opacity** slider for the recent items overlay, from 0% to 100%. The default is 25%.
- Added **Delete Profile** to remove a selected saved profile after confirmation. Renamed the existing copy action to **Copy Profile**.
- Tightened the Saved Profiles layout and highlighted confirmation buttons in red.
- Saved Profiles opens on **Current**. Copy Profile is disabled for the active save, and Delete Profile resets its tracker data after confirmation.
- When all tracker tabs are hidden, the tracker shows an Easter Egg icon and a reminder to re-enable a tab in Settings.

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
