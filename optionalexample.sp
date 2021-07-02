#undefine REQUIRE_PLUGIN
#tryinclude "motdmenu.inc"
#define REQUIRE_PLUGIN

//usual optional mod stuff
public void OnAllPluginsLoaded() {
#if defined MOTD_MENU
	g_bMotdMenuLoaded = LibraryExists("motdmenu");
#endif
}
 
public void OnLibraryRemoved(const char[] name) {
#if defined MOTD_MENU
	if (StrEqual(name, "motdmenu")) g_bMotdMenuLoaded = false;
#endif
}
 
public void OnLibraryAdded(const char[] name) {
#if defined MOTD_MENU
	if (StrEqual(name, "motdmenu")) g_bMotdMenuLoaded = true;
#endif
}

public void OnPluginEnd() {
#if defined MOTD_MENU
	if (g_bMotdMenuLoaded) CloseAllMenus();
#endif
}

//with these mocks allow you to use MotdMenu reguardless of compiling with it or not
// you basically don't have to do any other check for motd menu when using these
#if !defined MOTD_MENU
typedef MotdIconPathProvider = function bool(const char[] menuInfo, char[] iconPath, int iconPathSize);
#define DisplayMotdMenu(%1,%2,%3) DisplayMenu(%1,%2,0)
#define CreateMotdMenu(%1,%2) CreateMenu(%1,%2)
#define CancelMotdMenu(%1) CancelMenu(%1)
stock void CloseMotdMenu(Menu menu) { CancelMenu(menu); delete menu; }
#define Client_CheckMotdMenu(%1) false
#define CloseAllMenus()
methodmap MotdMenu < Menu {
	public MotdMenu(MenuHandler handler, MenuAction actions = MENU_ACTIONS_DEFAULT) { return view_as<MotdMenu>(CreateMenu(handler, actions)); }
	public bool DisplayMotd(int client, MotdIconPathProvider icons = INVALID_FUNCTION, int time = MENU_TIME_FOREVER) { this.Display(client, time); }
	public void Cancel() { this.Cancel(); }
	public void Close() { CloseMotdMenu(this); }
}
#endif