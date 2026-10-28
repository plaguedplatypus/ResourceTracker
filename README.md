# Resource Tracker

Track resources across the gathering skills with automatic chat and inventory tracking, customizable goals, and a compact in-game interface.

# Features:

- Automatic resource tracking through supported inventory and chat events.

- Support for Mining, Woodcutting, Fishing, Archaeology, Farming, Divination, Hunter, and Invention resources.

- Tracking of supported porter deliveries, Invention components, and special resource rewards.

- Compact resource list with skill/category filters and sorting.

- Resource counts and customizable collection goals.

- Persistent counts and settings between game sessions.

# Use the Tracker:
Use the icon tabs at the top to choose a skill. The left and right arrows reveal more skills when they do not all fit. All shows every visible skill; when only one skill tab is enabled, that skill replaces All. The buttons below the tabs change the sort order between Recent, A-Z, and Count. Some skills also offer a group filter. Archaeology lists materials first, followed by an ARTEFACTS section.

Each row shows a resource, its count, and an icon. When the game does not provide an item icon, the tracker uses the icon for the related skill. Select a row to open its item controls:

- Enter a number and select the pencil to set the count.
- Enter a number and select the star to set a goal.
- Select the eraser to clear a goal.
- Select the pin to keep a resource above unpinned rows in every sort order. Select it again to unpin the resource.
- Select the circular arrow twice to reset a count.
- Select the bin twice to remove a resource.

Select the same resource again to close its controls.

# Settings, sessions, and history:
Open the plugin's settings cog in Manage Plugins to control icons, goals, artefacts, and which skill tabs appear in the tracker. Turning off Display Artefacts hides artefact rows and the ARTEFACTS heading without deleting their counts. To remove every tracked row from one skill, select Clear beside that tab and then Confirm. Clearing a tab leaves session totals and daily history intact.

Select the Note-Pad tab to open the separate Session window. Use This session to see resources gathered since the first tracked gain after logging in and their items per hour. Active time pauses one minute after the last gain. Logging out ends the session.

Use Daily history in the same window to see counts and items per hour for each recorded day.

# EULA

This Plugin uses software licensed by Jagex to the developer under the terms of the Jagex End User Licence Agreement (EULA) found at https://legal.jagex.com/docs/terms/eula (and all terms incorporated into it by reference). The development and any use of the Plugin is at all times subject to the Jagex EULA.


# Permissions

chatAccess

Used to identify resource gains through in-game messages, including porter deliveries, Invention materials, Archaeology materials, and other supported gathering rewards.

trackingAccess

Used to obtain a RuneScape-provided tracking identifier so resource counts, collection goals, session history, and settings can be associated with the correct player account.

Combined use

Both permissions support accurate resource tracking and account-specific progress. Chat messages are processed to identify relevant resource gains, while the tracking identifier associates saved progress with the appropriate account.



# Data Protection  (Case 1)

Resource Tracker uses game information made available through the RuneScape API, including resource-related chat messages, inventory item IDs and quantities, and user-entered resource tracking information.

Tracked resource counts, collection goals, and plugin preferences are stored locally using the plugin persistence system.

This information is used solely to provide resource tracking and related functionality within the game.

The plugin does not transmit collected information to external servers or third parties.

Users can adjust or clear their stored tracking information using the available plugin controls.
