# Motd Menu

This library allows plugins to display VGUI Menus as nice web interface in the
Motd window. Motd Menus are set up almost identical to regular menus.
Additionally plugin developers can decide to display icons on the Motd version
of menus.

Menus need to be written with MotdMenu in order to work properly. While a
plugin could theoretically render out any menu, i didn't see an easy way to
get the MenuHandler.

When displaying a menu in the motd, all menu data is first piped into a 
database. From there a php script builds the Motd page and it is displayed.
Menu actions done in the Motd browser are piped back into the server through
rcon and then sent to the original MenuHandler.

This system probably works on other games as well, but I have only tested it on
TF2. Vote menus are currently also not supported. Although it would probably be
really nice to see vote results visually, I don't like the idea of having a
full-screen vote menu pop up.

## Features

Motd menus can be turned off in !settings and they also detect if clients
disabled html motds. In that case the players will just receive a regular VGUI
menu.

Keep in mind that `cl_disablehtmlmotd` is only checked with 1 player/second,
so refreshing that value could take some time. I could query that value more
often but I don't think it's worth it.

Users can also choose to have the menu displayed in a bigger motd screen
instead of the small blackboard screen TF2 normally uses, but that currently
does not affect rendering at all.

## Commands

There's one server command `sm_motdmenu_callback` for rcon - don't use it.

## Installation

1) Download the plugin and put it in your addons folder as usual.
2) Loading the plugin now will fail, but generate it's config if missing.
3) Edit the plugin config (see below).
4) Put the web content on your php server.  
   Don't use too many subdirectories as the url with additional data added must
   not exceed something like 150 chars.
5) Edit the web config (see below).
6) Reload the plugin in your server.

One web setup can handle mutliple servers.

If you install a plugin that uses MotdMenu and provides icons, you probably
need to put those image resources into the `img` web directory.

### Plugin Config

The Config is located in addons/sourcemod/configs/motdmenu.cfg

- `serverid` is the name php will know what server to notify. Allowed
  characters are `a`-`z` `A`-`Z` `0`-`9` and `_`
- `baseurl` is the public address of where the web page resides.
  For example `https://myserver.net/motdmenu/`.  
  Don't use too many subdirectories as the url with additional data added must
  not exceed something like 150 chars.
- `database` the database entry from `databases.cfg` to use to talk to the motd.

There are also three sounds in this config, those are basically copies of the
menu sound values in the core config of sourcemod, but maybe you want different
menu sounds for Motd Menu

### Web Config

This config is `settings.php`. Yes I could have used a key value file you're
used to, but storing data in a php script is less likely to leak in case of
misconfiguration.

- `database` is the database to connect to for data exchange. This needs to be
  the same across all game servers using this web instance. The values are
  pretty much the same as used in `databases.cfg`.
- `servers` is the list of servers to talk to. Every entry in this list needs
  to be named exactly the same as the server `serverid` value.  
  - `name` is currently pretty unused, but displayed at the top of motd menus.
  - `host` is your game servers ip address.
  - `port` is the game servers port. Usually thats 27015.
  - `rconpass` is the rcon password. Please choose a strong one so nobody can
    guess it and break your server from outside. 

## Developing

Basic usage of motd menus does not differ a lot from regular VGUI menus. There
are only a hand full of command that you need:

| VGUI Menu | MOTD Menu | Comment |
|-----|-----|-----|
| `CreateMenu`<br>`new Menu` | `CreateMotdMenu`<br>`new MotdMenu` |  |
| `DisplayMenu`<br>`Menu.Display` | `DisplayMotdMenu`<br>`MotdMenu.DisplayMotd` | Only the method map will automatically fall back to `Menu.Display` if Motd Menus are disabled |
| `CancelMenu`<br>`Menu.Cancel` | `CancelMotdMenu`<br>`MotdMenu.Cancel` | Will hide the menu, again should fall back to `CancelMenu` if not Motd Menu is open |
| `delete menu` | `CloseMotdMenu`<br>`MotdMenu.Close` | This call is necessary to remove some additional resources the plugin needs to store to make callbacks from the motd browser work |

The methodmap tries to hide away the logic for optional includes. So if you
include `motdmenu.inc` optional, the `MotdMenu` methodmap automatically
proxies to `Menu` if motd menus is not loaded. To not have the include as
compile time requirement you'll need to some preprocessor magic.

As a nice little bonus you can provide an image for ever menu option displaying
in the MOTD. All you need to do for that is to pass a `MotdIconPathProvider` to
the `DisplayMotdMenu`/`MotdMenu.DisplayMotd` call. In this function you receive
the info data you pass into the menu item back and can map it to a image path.

```c#
// MotdIconPathProvider for a fruit menu
bool GetMenuFruitIcon(const char[] menuInfo, char[] iconPath, int iconPathSize) {
	Format(iconPath, iconPathSize, "img/fruitmenu/fruit_%s.png", menuInfo);
}
void ShowFruitMenu(int client) {
	char translated[64];
	MotdMenu menu = new MotdMenu(FruitMenuHandler, MENU_ACTIONS_DEFAULT);
	menu.SetTitle("%T", client, "pick fruit");
	Format(translated, sizeof(translated), "%T", client, "fruit banana");
	menu.AddItem("banana", translated);
	Format(translated, sizeof(translated), "%T", client, "fruit orange");
	menu.AddItem("banana", translated);
	menu.DisplayMotd(client, GetMenuFruitIcon, MENU_TIME_FOREVER);
}
if(action == MenuAction_Select) {
	// ...
} else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
	// ...
} else if(action == MenuAction_End) {
	CloseMotdMenu(menu);
}
```

I recommend requiring image resources for your menus to be in the web directory
in `img/plugin/image.png` so they don't clash with other plugins but allowing
the server admins to exchange images if they so desire.

When your plugin unload it's recommended that you call `CloseAllMenus`. This
will invalidate and close all motd menus currently opened by your plugin to
prevent the console spamming useless errors when your plugin reloads.

## Dependencies

You'll need smlib to compile the plugin.
The web part was written on PHP 7.2.

## Plans

The plugin shall grow as my requirements grow, and I'll be using it in my main
project from now on.

Suggestions and feedback are welcome, but I don't know if or how fast I'll add
stuff to this plugin.

### Thank you

Thank you to psychonic for writing Dynamic MOTD, it was a very helpful
resource. Also thank you to the sourcemod community and discord guild for
answering my questions. Lastly I want to thank Fuffeh for supporting the
idea.