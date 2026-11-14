# Resource Tracker

Resource Tracker records supported resources as you gather them, so you can see your totals without counting every drop. Open its compact in-game panel to follow a collection goal, browse resources by skill, or check how much you gathered during a session and each day.


## Known Issues
- Currently waiting for live release for any known issues.

## Additions
- This is where planned additions will be listed.


## What it tracks

The plugin detects supported gains from your inventory and relevant game messages. It covers Mining, Woodcutting, Fishing, Archaeology, Farming, Divination, Hunter, and Invention resources, along with supported porter deliveries, Invention components, Seren spirit gifts, Player Owned Ports.

Only supported gains are counted on the ordinary resource tabs. They start recording new gains while the plugin is active; they do not import resources you gathered earlier. Ports stock is read as described below.

## Using the tracker

Open Resource Tracker from the Plugin Hub ribbon and gather a supported resource. It appears as a row with its name, icon, and count. If the game does not provide an item icon, the tracker shows the related skill icon.

Use the icon tabs to view a skill or resource, or choose the **bag tab** to see resources across all visible skills. The arrows reveal tabs that do not fit in the panel.

Sort rows by **Recent**, **A-Z**, or **Count**. Some skills also offer additional item and zone filters.

Select a row to open its controls, and select it again to close them:

- Enter a number and select the **Pencil** to correct the count.
- Enter a number and select the **Star** to set a collection goal. The row then shows your progress toward it; the **Eraser** clears the goal.
- Select the **Pin** to keep the resource above unpinned rows in every sort order. Select it again to unpin.
- Select the **Circular Arrow** twice to reset the count, or the **Bin** twice to remove the row.

Manual count corrections change the tracker row without adding to session or daily gathering totals.

Invention material rows also show **Owned** beneath their controls. This is the current amount in your Materials pouch. The number in the row remains the amount tracked as gained by Resource Tracker.

## Player Owned Ports

-Choose the **anchor tab** for Player Owned Ports. Use its group picker to show **All groups**, **Ports Resources**, **Trade Goods**, or **Ship Rewards**. 

-The tab reads your Ports stock directly, you do not need to open the Ports Resources panel. Each stock row shows the gains observed by Resource Tracker; select it to view the current **Owned** amount. 

-The owned amount shows **(MAX)** when it reaches that resource's cap. 200k for Chimes and 999k for the other resources. Trade Goods **(MAX)** at 250. Spending a resource updates the owned amount without reducing the amount tracked as gained by Resource Tracker.

-All Ports rows have a **Goal** field, **Star** to set the goal, **Eraser** to clear it, and **Circular Arrow** to reset that row's tracked gains with a second click to confirm. Goal progress uses tracked gains, not Owned stock.

-Use **Reset gains** beside Player Owned Ports in Settings to clear all observed Ports gains while keeping the latest stock amounts and saved goals.

<img src="https://image.modcdn.io/members/20c3/63901461/profile/2026-11-0802_38_03-runescape.png" alt="Resource Tracker panel" width="358" height="414">

## Sessions and daily history

Select the **Notepad** tab to open the separate Session window. **This Session** shows the resources gathered since the first tracked gain after login, including counts and items per hour.

Active time pauses after one minute without a resource gain, and logout ends the session.

Select **New Session** to clear the current session; the next tracked gain starts a fresh one without clearing daily history.

**Daily History** shows counts and items per hour for each recorded UTC day. Choose a day from the list to review it, or clear the saved history in that window.

<img src="https://image.modcdn.io/members/20c3/63901461/profile/rtsession2.png" alt="Session and daily history" width="400" height="346">

## Settings and saved progress

Select the **settings button** at the right of Resource Tracker's bottom bar to open its settings window.

<img src="https://image.modcdn.io/members/20c3/63901461/profile/2026-11-0802_43_50-runescape.png" alt="Settings button" width="182" height="119">

There you can choose which skill tabs appear and whether to show item icons, goals, and Archaeology artefacts. Hiding artefacts leaves their counts saved.

To remove every tracker row for one skill, select **Clear** beside that skill and then **Confirm**. This leaves session totals and daily history intact.

Under **Saved Profiles**, choose another character's local save, then select **Use profile** and **Confirm replace**. This copies that profile's counts, goals, settings, and history over the current character's save. The source profile remains available.

Select **Delete all data** and **Confirm delete** to erase Resource Tracker's saved data and characters on the device. Other plugins' data is unaffected.

Counts, goals, Ports stock and observed gains, settings, and daily history are saved locally for each player account.

<img src="https://image.modcdn.io/members/20c3/63901461/profile/rt-settings.png" alt="Resource Tracker settings" width="450" height="270">

Use the eye button at the left of the bottom bar to hide or show the Plugin Hub ribbon. Hiding it gives the tracker more room.

<img src="https://image.modcdn.io/members/20c3/63901461/profile/ribbon1.png" alt="Plugin Hub ribbon shown" width="300" height="207"> <img src="https://image.modcdn.io/members/20c3/63901461/profile/ribbon2.png" alt="Plugin Hub ribbon hidden" width="300" height="207">


## Requirements

Resource Tracker requires PrettyUI for its interface.

## Contact and feedback

Bug reports, feedback, and collaboration ideas are welcome in this page's discussion or the Resource Tracker channel in the [Discord](https://discord.com/channels/1523582684109082645/1561866361783853096).

## EULA

This Plugin uses software licensed by Jagex to the developer under the terms of the Jagex End User Licence Agreement (EULA) found at [https://legal.jagex.com/docs/terms/eula](https://legal.jagex.com/docs/terms/eula) (and all terms incorporated into it by reference). The development and any use of the Plugin is at all times subject to the Jagex EULA.

## Permissions

| Permission | Why it is needed |
| --- | --- |
| `chatAccess` (required) | Identifies resource gains through in-game messages, including porter deliveries, Invention materials, Archaeology materials, and other supported gathering rewards. |
| `trackingAccess` (optional) | Provides a stable character ID for saving resource counts, goals, session history, and settings. |

With tracking access, Resource Tracker links your character name and ID to the same save. It waits for the ID after login so a name change cannot start a separate save. If tracking access is turned off later, the name can still open that save. Without tracking access, the plugin saves under your current character name instead. Granting tracking access later links the ID to that existing save. Changing your name while tracking access is unavailable can make a name-only save inaccessible under the new name.

## Data Protection (Case 1)

Resource Tracker uses game information made available through the RuneScape API, including resource-related chat messages, inventory item IDs and quantities, Invention material balances, Player Owned Ports resource amounts sent to the client, and user-entered resource tracking information.

Tracked resource counts, Ports stock and observed gains, collection goals, plugin preferences, and the character name-to-ID link are stored locally using the plugin persistence system.

This information is used solely to provide resource tracking and related functionality within the game.

The plugin does not transmit collected information to external servers or third parties.

Users can adjust or clear their stored tracking information using the available plugin controls.
