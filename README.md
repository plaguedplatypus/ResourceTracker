# Plague's Resource Tracker

Plague's Resource Tracker records resources you gather while playing RuneScape. It appears in the docked **Plugins** panel and keeps a running count for each resource.

## Get started

1. Enable **Plague's Resource Tracker** in the Plugins panel.
2. Select its ribbon icon to open the tracker.
3. Gather a resource. The tracker adds it when RuneScape reports the gain.

Items already in your backpack when the plugin starts establish its starting point. They do not count as newly gathered resources.

### Permissions

The tracker requires **tracking access** to save counts, goals, settings, session history, daily history, and learned item icons separately for each character. It also requires **chat access** to count rewards that RuneScape sends directly to your bank, material storage, or chat, including Archaeology, Invention, Farming, and Seren spirit rewards.

## Use the tracker

Use the icon tabs at the top to choose a skill. The left and right arrows reveal more skills when they do not all fit. **All** shows every visible skill. The buttons below the tabs change the sort order between **Recent**, **A-Z**, and **Count**. Some skills also offer a group filter. Archaeology lists materials first, followed by an **ARTEFACTS** section.

Each row shows a resource, its count, and an icon. When RuneScape does not provide an item icon, the tracker uses the icon for the related skill. Select a row to open its item controls:

- Enter a number and select the pencil to set the count.
- Enter a number and select the star to set a goal.
- Select **X** to clear a goal.
- Select the circular arrow twice to reset a count.
- Select the bin twice to remove a resource.

Select the same resource again to close its controls.

## Settings, sessions, and history

Open the plugin's settings cog in Manage Plugins. The **Settings** page controls icons, goals, and which skills appear in the tracker.

The **This session** page shows resources gathered since logging in and their items per hour. Active time pauses 30 seconds after the last gain. Logging out ends the session.

The **Daily history** page shows the same counts and items per hour for each recorded day. Prices, item values, Grand Exchange prices, and GP per hour are not included.

## What gets counted

The tracker recognizes gathering resources from Mining, Woodcutting, Fishing, Archaeology, Farming, Invention, Divination, Hunter, and Seren spirit rewards. It compares backpack quantities with an initial baseline and ignores ordinary rearranging. It also recognizes supported delivery and reward messages.

Bank withdrawals, noted-item conversions, and similar item movements are excluded where RuneScape provides enough information to identify them. Manual changes update the tracker count but do not add to session or daily gathering totals.

## Saved data

Counts, goals, item icons, settings, session history, and daily history are saved automatically. The tracker continues recording while its docked panel is closed.

