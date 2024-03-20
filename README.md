# About HorizonFisher

This is a fork of [fisher](https://gitlab.com/svanheulen/fisher) that uses the fishing parameters and calculations that are specific to HorizonXI. It is not complete. Please report any aberrant behavior, feature requests, or praise to [bayesian.bee@gmail.com](bayesian.bee@gmail.com).

Horizonfisher also includes GM-evasion functionality that attempts to thwart _some_ bot checks that Horizon GMs perform. It is also not complete.

### Display of Identified Fish

For the most part fisher will only display the exact fish or item you have hooked, but there are a few special cases:

* Fisher will always confuse `1 gil` and `100 gil`.
* Fisher will always confuse `mithran snare` and `tarutaru snare`.
* Fisher will always confuse `crayfish` and `ulbukan lobster` while in Ulbuka.
* Fisher will always confuse `king perch` and `malicious perch` while in Ulbuka.
* Under certain conditions, fisher may confuse `fish scale shield` and `rusty pick`.
* Under certain conditions, fisher may confuse `adoulinian kelp` and `hard-boiled egg`.
* Under certain conditions, fisher may confuse the number of `tiny goldfish` hooked.

### Equipment Restrictions

Automatic fishing will not start and fish/item identification will not work if any of the following items are equipped:

* A `maze monger fishing rod` while not inside Everbloom Hollow
* A `peguin ring`, even if it's not activated

# Installation

The latest stable version is always available [here](https://svanheulen.gitlab.io/fisher/fisher.zip).

Extract the archive to your `addons` folder, which by default you can find inside the same folder as the `Windower.exe`.

# Usage

## Load and Unload

```
//lua load horizonfisher
//lua unload horizonfisher
//lua reload horizonfisher
```

## Specify Catch and Bait

```
//horizonfisher add <item_name>
//horizonfisher remove <item>
//horizonfisher list
```

OR

```
//hf add <item_name>
//hf remove <item>
//hf list
```

There is no need to use the same capitalization as the game, and you can also use both the short and long names.
When removing a fish, item or bait you can also use the item ID instead of the name.

There are also special names that can be used for adding and removing groups of items:

| Name | Description |
| --- | --- |
| `all` | All fishes, items and baits |
| `all fish` | All fishes |
| `all item` | All items |
| `all bait` | All baits |
| `monster` | All monsters |
| `unknown` | Anything that can't be identified by fisher |

Here are some examples:

```
//horizonfisher add moat carp
//horizonfisher add CrAyFiSh
//horizonfisher add insect ball
//horizonfisher add ball of insect paste
//horizonfisher add all fish
//horizonfisher remove Moat Carp
//horizonfisher remove 4472
//horizonfisher remove all
//horizonfisher list
```

## Start and Stop Automatic Fishing

> You will need to add at least one fish/item and one bait before starting automatic fishing.

```
//horizonfisher start [catch_limit]
//horizonfisher stop
```

When starting automatic fishing, you can also specify the optional `catch_limit` to stop fishing after the specified number of catches.

Automatic fishing will also stop under the following conditions:
* Your receive a certain number of "You didn't catch anything." messages in a row.
* Your specified catch limit is reached
* You run out of bait
* You run out of inventory space
* You are targeted by an action
* Your player status changes to something other than fishing or idle
* You receive a chat message from a GM
* You perform any action other than `/fish`
* You manually perform any fishing action
* You change zones or log out
* You have a `maze monger fishing rod` equipped, and you're not inside Everbloom Hollow
* You have a `penguin ring` equipped, even if it's not activated
* Casting fails multiple times in a row

## Without Automatic Fishing

When horizonfisher is loaded but the automatic fishing is not started it will still track fishing fatigue and display the name of the catches you hook.

## Adjusting catch time parameters

Horizonfisher will automaticaly calculate the amount of time it takes to reel in a fish based on the fishing minigame parameters sent by the server. However, you can control that calculation by specifying a minimum, maximum, and 

```
//hf catch_delay_min 3
//hf catch_delay_tweak 15
//hf catch_delay_max 30
```

The effects of these settings are described below.

## Advanced Settings

To modify these setting you will need to edit the settings file manually.
There will be an XML file named after your character, inside fisher's data folder.

> If fisher is loaded, you will need to unload it first before modifying the settings file.

Here are the available advanced settings:

| Name | Description | Default |
| --- | --- | ---: |
| `equip_delay` | The amount of time in seconds to wait after equipping bait. *If you set this value too low, you may have failed casts after bait is equipped.* | 2 |
| `move_delay` | The amount of time in seconds to wait after moving items between bags. | 0 |
| `cast_attempt_delay` | The amount of time in seconds to wait before retrying to cast your fishing rod. | 3 |
| `cast_attempt_max` | The maximum number of times to attempt casting your fishing rod if fishing does not start. | 3 |
| `release_delay` | The amount of time in seconds to wait before releasing a hooked item that's not in your catch list. | 3 |
| `catch_delay_min` | The minimum amount of time in seconds to wait before reeling in a hooked item. | 3 |
| `catch_delay_tweak` | The catch delay for fish near your level, which will be adjusted based on the difference between player skill and fish level. | 15 |
| `catch_delay_max` | The maximum amount of time in seconds to wait before reeling in a hooked item. | 30 |
| `recast_delay` | The amount of time in seconds to wait after fishing ends to recast your fishing rod. | 3 |
| `no_hook_max` | The number of consecutive "You didn't catch anything" messages before automatic fishing is stopped. *A value of zero will disable this feature.* | 20 |
| `debug_messages` | Specifies if debug messages should be output to the chat log. | false |
| `alert_command` | A string that will be passed to `windower.send_command` when fisher stops automatically. *An empty string will disable this feature.* | *empty string* |

## Anti-GM

### Geofence mode ("No-hoe-check mode")

This bot can react to meddling GMs! On HorizonXI, GMs rotate or reposition characters suspected of fishbotting to see how they react. This addon detects movement and rotation using a [geofence](https://en.wikipedia.org/wiki/Geo-fence) that is checked on each incoming packet. If your character is moved outside of the geofence boundary or is rotated by a sufficiently large angle, the following takes place:
* The player is alerted with a message in the log and a highly-visible on-screen alert. The alert can be dismissed with `//horizonfisher dismiss`.
* The bot attempts to reel in a currently cast fishing line.
* Automatic fishing stops.
* The bot returns to the position they were in when `horizonfisher start` was called.
* The bot resumes fishing.

The above can be enabled by setting the `<enabled>` tag under the `<geofence>` tag to `true`. to true in the settings XML file. If you are using an older version of horizonfisher, please delete your settings file and let the addon regenerate a new one, then set the tags as above and restart the addon.

**Remember, this may not prevent you from being suspended or banned.** All botting is at your own risk, and the best way to avoid getting caught is to bot less, and to never bot away from your keyboard. Take it from me, as I lost a character doing this. :)

### Dry detection [BETA]

Continuing to fish into an empty pool for several minutes is supicious, and seasoned non-botting fishermen will notice. With dry detection enabled, the bot will stop fishing after it fails to catch a target fish X times. You can set X with the `<no_catch_limit>` tag in the settings file.

The above can be enabled by setting the `<enabled>` tag under the `<dry_detection>` tag to `true`. to true in the settings XML file. If you are using an older version of horizonfisher, please delete your settings file and let the addon regenerate a new one, then set the tags as above and restart the addon.

# Development & Maintenence

## The path to 1.0

* A visualizer that displays fish catches similar to how neuronal action potentials look on a voltage trace, and fish per hour. 
* Logging of cast outcomes with timestamps (real time and full ingame time)
* Detection of AFK check messages.

## Changelog

0.8.3
* Updated readme
* Three-eyed fish fix

0.8.2
* Updated addon author.

0.8.1
* No longer gives an error when the server prints a message.
* Added `catch_delay_max`, `catch_delay_min`, and `catch_delay_tweak` comamnds.
* Removed extraneous fatigue-related configuration variables.
* Fixed Lik.

0.8.0
* BETA: Added dry detection, a GM countermeasure that pauses fishing until pools are restocked when hooks are slow.
	* Known issue: The no-catch counter doesn't always reset when restocks happen.
* Added universal parameter offset fix (aka Universal Ebisu Fix).
* Reorganized anti-gm blocks in settings.xml.
* Server messages no longer stop horizonfisher. 
* Removed the fatigue command, and fatigue information from settings.xml.
* Removed the legacy no_hook_max functionality.
* Removed extraneous UID enumerating debug messages
* Fixed Titanictus, Gugrusaurus, Titanic Sawfish, and Ryugu Titan, Gigant Squid (for real i hope)

0.7.3
* Updated data for ryugu titan and titanic sawfish
* Added an as-of-yet unused per-zone fishing message offset map to data.lua.

0.7.2
* As of 2023-10-28, Horizon no longer subtracts 1 from the stamina depletion parameter. This hotfix deals with it.

0.7.1
* Shortened the addon name in messages.
* Fishing params appear alongside "unknown" messages
* Replaced "act natural" anti-GM functionality with return-to-fishing functionality.

0.7.0.5
* Made fishing params on by default.

0.7.0.4
* Speculatively fixed Ryugu Titan and Gugrusaurus
* Looks like some high level fish may be higher level on retail than on horizon, affecting their Stamina values.

0.7.0.3
* Re-fixed gigant squid.
* Fixed Titanictus and Titanic Sawfish

0.7.0.2
* Fixing elshimo frog/newt
* Moving changelog in README

0.7.0.1
* Added the shortcut addon command `//hf`
* Adjusted gigant squid parameters.

0.7.0.0
* Added anti-GM technology that reacts to being pos hacked or zoned.

0.6.3.1
* Corrected arrow_duration for forest carp.

0.6.3.0
* Fixed a mismatch between sever-calculated stamina depletion and addon-calculated stamina depletion introduced by floating point arithmetic errors

0.6.2.4
* Fixed a bug in which error messages would not display under most circumstances.