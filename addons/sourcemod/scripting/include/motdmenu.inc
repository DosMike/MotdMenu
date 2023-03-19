#if defined MOTD_MENU
 #endinput
#endif
#define MOTD_MENU

#define MOTDMENU_VERSION_YEAR 23
#define MOTDMENU_VERSION_WEEK 11
#define MOTDMENU_VERSION_BUILD 'a'
#define MOTDMENU_VERSION "23w11a"

/**
 * A mapper that provides an image path for the motd browser for the specified menu item
 *
 * @param menuInfo      the info string for the menu item
 * @param iconPath      write an image path here, can be an absolute https url
 * @param iconPathSize  the size of iconPath
 * @return true if the item has an icon
 */
typedef MotdIconPathProvider = function bool(const char[] menuInfo, char[] iconPath, int iconPathSize);


/** 
 * Tries to open the menu in the clients motd browser. Note that opening the motd
 * panel only happens after menu information was written to the database.
 * 
 * @return true if the motd was opened, false if cl_disablehtmlmotd or client preferences blocked
 */
native bool DisplayMotdMenu(Menu menu, int client, MotdIconPathProvider icons = INVALID_FUNCTION);

/** 
 * Since the menu handler cannot be fetched from a menu handle, this function will
 * create a menu for you, and store the handler for motd callbacks.
 * 
 * @note close the handle with CloseMotdMenu(MotdMenu) or MotdMenu.Close(); your
 *       plugin owns the menu handle, but motd menu needs to release the handler
 *       and actions when the menu is closed
 * @return a MotdMenu handle extending Menu
 */
native Menu CreateMotdMenu(MenuHandler handler, MenuAction actions = MENU_ACTIONS_DEFAULT);

/** 
 * Closes the motd page, if it's marked as showing a menu, then call Cancel on the 
 * menu and closes the menu handle. The variable passed in will be cleared to INVALUD_HANDLE.
 */
native void CloseMotdMenu(Menu& menu);

/** 
 * Tries to remember if a motd menu is open and closes it. Additionally will cancel
 * the normal menu.
 */
native void CancelMotdMenu(Menu menu);

/** 
 * The html convar is only checked up to once every minute as it should not toggle
 * too often anyways. Changes in client prefs are reflected immediately.
 * Can be used to style your menu differently for motd menus. Should not be used
 * to lock out features! In bird culture this is considered a dick move.
 * @return true if the client enabled MotdMenu and has html motd enabled
 */
native bool Client_CheckMotdMenu(int client);

/** 
 * Closes all menus that you currently opened to any player.
 * Should be called whenever your plugin unloads, so hooks can neatly be removed.
 */
native void CloseAllMenus();

/**
 * Set this flag from library related forwards
 */
#if defined REQUIRE_PLUGIN
stock bool g_bMotdMenuLoaded = true;
#else
stock bool g_bMotdMenuLoaded = false; //wait for plugin load
#endif

/**
 * This method map uses g_bMotdmenuLoaded to automatically determin whether to try
 * and use the natives or not. So if you use MotdMenu optional, you just need to
 * update the flag in the usual places and you can use this methodmap without any
 * other thought.
 */
methodmap MotdMenu < Menu {
	
	/**
	 * Pipes menu creation through MotdMenu to retrieve the menu handler.
	 * This is required to call the menu callback, when the client clicks an item in the motd.
	 * 
	 * @note close the handle with CloseMotdMenu(MotdMenu) or MotdMenu.Close(); your
	 *       plugin owns the menu handle, but motd menu needs to release the handler
	 *       and actions when the menu is closed
	 */
	public MotdMenu(MenuHandler handler, MenuAction actions = MENU_ACTIONS_DEFAULT) {
#if defined REQUIRE_PLUGIN
		return view_as<MotdMenu>(CreateMotdMenu(handler, actions));
#else
		if (g_bMotdMenuLoaded) {
			return view_as<MotdMenu>(CreateMotdMenu(handler, actions));
		} else {
			return view_as<MotdMenu>(CreateMenu(handler, actions));
		}
#endif
	}
	
	/** 
	 * Opens the menu in the clients motd browser, if setting permit. Otherwise tries
	 * to open a standard menu with the give timeout. Note that opening the motd panel
	 * only happens after menu information was written to the database.
	 *
	 * @param client  the client to open the menu for
	 * @param icons   the "info -> uri path" mapper
	 * @param time    max time to display the fallback menu for in seconds
	 * @return true on success
	 *
	 * @see Menu.Display or DisplayMenu
	 */
	public bool DisplayMotd(int client, MotdIconPathProvider icons = INVALID_FUNCTION, int time = MENU_TIME_FOREVER) {
#if defined REQUIRE_PLUGIN
		if (DisplayMotdMenu(this, client, icons))
			return true;
#else
		if (g_bMotdMenuLoaded) {
			if (DisplayMotdMenu(this, client, icons))
				return true;
		}
#endif
		return this.Display(client, time);
	}
	
	public void Cancel() {
#if defined REQUIRE_PLUGIN
		CancelMotdMenu(this);
#else
		if (g_bMotdMenuLoaded) {
			CancelMotdMenu(this);
		} else {
			CancelMenu(this);
		}
#endif
	}
	
	public void Close() {
		Menu close = this;
#if defined REQUIRE_PLUGIN
		CloseMotdMenu(close);
#else
		if (g_bMotdMenuLoaded) {
			CloseMotdMenu(close);
		} else {
			CancelMenu(close);
			delete close;
		}
#endif
	}
	
};


public SharedPlugin __pl_motdmenu = 
{
    name = "motdmenu",
    file = "motdmenu.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_motdmenu_SetNTVOptional()
{
	MarkNativeAsOptional("CreateMotdMenu");
	MarkNativeAsOptional("CloseMotdMenu");
	MarkNativeAsOptional("DisplayMotdMenu");
	MarkNativeAsOptional("CancelMotdMenu");
	MarkNativeAsOptional("Client_CheckMotdMenu");
}
#endif