#include <clientprefs>
#include <smlib>
#include <menus>
#include <motdmenu>

#pragma newdecls required
#pragma semicolon 1

#define CONFIG_PATH "addons/sourcemod/configs/motdmenu.cfg"
#define CONFIG_PATH_CORE "addons/sourcemod/configs/core.cfg"
#define COOKIE_ENABLED "clientMotdmenuEnabled"
#define COOKIE_BIGMOTD "clientMotdmenuBig"

Database g_database;
bool g_bDBconnected;
bool g_bEngineIsTF2;

// enum taken from dynamic_motd
enum /* Ep2vMOTDCmd */ {
	Cmd_None,//0
	Cmd_JoinGame,//1
	Cmd_ChangeTeam,//2
	Cmd_Impulse101,//3
	Cmd_MapInfo,//4
	Cmd_ClosedHTMLPage,//5
	Cmd_ChooseTeam,//6
};

enum struct SMenuExtra {
	Menu handle;
	Handle owner; //plugin
	MenuHandler callback;
	MenuAction filter;
}
ArrayList MenuExtra;
Menu clientActiveMotdMenu[MAXPLAYERS+1];
bool clientIgnorePanelsClosing[MAXPLAYERS+1];

char g_serverId[16];
char g_dbserverId[24];
char g_motdmenuwwwbase[150];
bool g_clientDisablehtmlmotd[MAXPLAYERS+1]; //by convar (all html motds)
bool g_clientDisablemotdmenu[MAXPLAYERS+1]; //by cookie (only motd menus)
bool g_clientMotdSwitchBig[MAXPLAYERS+1]; //by cookie (tf2 only, bigger motds)
int g_clientButtons[MAXPLAYERS+1]; //used to cancel motd menus

char g_coreMenuSoundSelect[PLATFORM_MAX_PATH];
char g_coreMenuSoundExit[PLATFORM_MAX_PATH];
char g_coreMenuSoundExitBack[PLATFORM_MAX_PATH];

public Plugin myinfo = {
	name = "MOTD Menus",
	author = "reBane",
	description = "Display menus in the motd if possible",
	version = MOTDMENU_VERSION,
	url = "N/A"
}

// --== BASE EVENTS ==--

public void OnPluginStart() {
	
	// load translations and config
	
	LoadTranslations("core.phrases");
	
	if (MenuExtra == null)
		MenuExtra = new ArrayList(sizeof(SMenuExtra));
	else
		MenuExtra.Clear();
	
	char database[64];
	
	KeyValues config = new KeyValues("motdmenu");
	if (config.ImportFromFile(CONFIG_PATH)) {
		config.GetString("database", database, sizeof(database), "default");
		config.GetString("baseurl", g_motdmenuwwwbase, sizeof(g_motdmenuwwwbase));
		config.GetString("serverid", g_serverId, sizeof(g_serverId));
		config.GetString("MenuItemSound", g_coreMenuSoundSelect, sizeof(g_coreMenuSoundSelect), "buttons/button14.wav");
		config.GetString("MenuExitSound", g_coreMenuSoundExit, sizeof(g_coreMenuSoundExit), "buttons/combine_button7.wav");
		config.GetString("MenuExitBackSound", g_coreMenuSoundExitBack, sizeof(g_coreMenuSoundExitBack), "buttons/combine_button7.wav");
		TrimString(g_serverId);
	} else {
		config.SetString("database","default");
		config.SetString("baseurl", "https://localhost/motdmenu");
		config.SetString("serverid","example");
		config.SetString("MenuItemSound", "buttons/button14.wav");
		config.SetString("MenuExitSound", "buttons/combine_button7.wav");
		config.SetString("MenuExitBackSound", "buttons/combine_button7.wav");
		KeyValuesToFile(config, CONFIG_PATH);
		delete config;
		ThrowError("Please review the config and reload the plugin: %s",CONFIG_PATH);
	}
	delete config;
	
	if (!strlen(g_serverId) || strcmp(g_serverId,"example",false)==0)
		ThrowError("serverid in config must be set! ('example' is invalid)");
	for (int i;i<strlen(g_serverId);i++) // quick /^\w+$/ check
		if (!('a'<= (g_serverId[i]|' ') <='z') && !('0'<=g_serverId[i]<='9') && g_serverId[i]!='_')
			ThrowError("serverid contains invalid characters. use only a-z A-Z 0-9 and _");
	if (!strlen(g_motdmenuwwwbase))
		ThrowError("baseurl in config must be set!");
	
	// hookeroo
	
	g_bEngineIsTF2 = GetEngineVersion() == Engine_TF2;
	RegServerCmd("sm_motdmenu_callback", Command_Callback, "Invoke menu actions from motd", FCVAR_HIDDEN|FCVAR_DONTRECORD);
	HookUserMessage(GetUserMessageId("VGUIMenu"), UserMsg_VGUIMenu, true);
	AddCommandListener(Event_ClosedHtmlpage, "closed_htmlpage");
	
	// register cookies
	
	RegClientCookie(COOKIE_ENABLED, "Enables or disables motd menus", CookieAccess_Public);
	if (g_bEngineIsTF2)
		RegClientCookie(COOKIE_BIGMOTD, "Uses a bigger motd screen", CookieAccess_Public);
	SetCookieMenuItem(cookieMenuHandler, 0, "Motd Menu");
	
	// connect to database
	
	g_bDBconnected = false;
	Database.Connect(Await_DatabaseConnected, database);
	PrintToChatAll("[MotdMenu] Version %s was loaded", MOTDMENU_VERSION);
}

public void OnPluginEnd() {
	NukeEntries();
}

public void OnClientConnected(int client) {
	clientIgnorePanelsClosing[client]=false;
	QueryClientConVar(client, "cl_disablehtmlmotd", Await_ClientConvar_Disablehtmlmotd);
}

public void OnClientDisconnect_Post(int client) {
	Impl_CancelMotdMenu(client, _, MenuCancel_Disconnected);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	//button change:
	int change = buttons ^ g_clientButtons[client];
	//key down edge:
	change &= buttons;
	//close motd menu if buttons were pressed
	if (change) {
		//there shouldn't really be any menu open if buttons change
		// most likely we pushed something on the database and the motd panel didn't open
		Impl_CancelMotdMenu(client, _, MenuCancel_NoDisplay);
	}
	g_clientButtons[client] = buttons;
}

public void OnMapStart() {
	CreateTimer(1.0, Timer_UpdateClientHtmlMotd, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	
	if (!PrecacheSound(g_coreMenuSoundSelect)) {
		PrintToServer("Could not precache sound %s", g_coreMenuSoundSelect);
	}
	if (!PrecacheSound(g_coreMenuSoundExit)) {
		PrintToServer("Could not precache sound %s", g_coreMenuSoundExit);
	}
	if (!PrecacheSound(g_coreMenuSoundExitBack)) {
		PrintToServer("Could not precache sound %s", g_coreMenuSoundExitBack);
	}
}

// --== Methods ==--

public Action Command_Callback(int args) {
	// has to be "sm_motdmenu_callback" <string:serverId> <int:userid> <int:action> <int:param1> <int:param2>
	if (GetCmdArgs() != 5) {
		LogError("[MotdMenu] Rcon Callback used invalid command structure!");
		return Plugin_Handled;
	}
	char buffer[16];
	GetCmdArg(1, buffer, sizeof(buffer));
	if (strcmp(g_serverId, buffer)) {
		LogError("[MotdMenu] Rcon Called wrong server instance (Target was %s but this is %s)!", buffer, g_serverId);
		return Plugin_Handled;
	}
	int userId, client, param1, param2;
	MenuAction action;
	GetCmdArg(2, buffer, sizeof(buffer));
	userId = StringToInt(buffer);
	client = GetClientOfUserId(userId);
	GetCmdArg(3, buffer, sizeof(buffer));
	action = view_as<MenuAction>(StringToInt(buffer));
	if (action == MenuAction_Select || action == MenuAction_Cancel) {
		param1 = client;
	} else {
		GetCmdArg(4, buffer, sizeof(buffer));
		param1 = StringToInt(buffer);
	}
	GetCmdArg(5, buffer, sizeof(buffer));
	param2 = StringToInt(buffer);
	
	if (action != MenuAction_Start) { //close first, so back menus that don't use MotdMenu work
		clientIgnorePanelsClosing[client]=true;
		CloseMOTDPanel(client);
	}
	DataPack pack = new DataPack();
	pack.WriteCell(userId);
	pack.WriteCell(action);
	pack.WriteCell(param1);
	pack.WriteCell(param2);
	pack.Reset();
	RequestFrame(Event_MotdMenuCallbackFrame, pack);
	return Plugin_Handled;
}
public void Event_MotdMenuCallbackFrame(DataPack pack) {
	int client = GetClientOfUserId( pack.ReadCell() );
	MenuAction action = view_as<MenuAction>( pack.ReadCell() );
	int param1 = pack.ReadCell(), param2 = pack.ReadCell();
	delete pack;
	
	clientIgnorePanelsClosing[client]=false;
	SMenuExtra mex;
	Menu menu;
	if (client < 1 || (menu=clientActiveMotdMenu[client]) == INVALID_HANDLE || FindMenuExtra(menu, mex) == -1) {
		return; //client is gone, or menu was already handled
	}
	// clear previous/active menu
	if (action != MenuAction_Start) {
		Impl_CancelMotdMenu(client, false);
	}
	// handle next menu
	MenuActionIndirect(mex, action, param1, param2);
}

public Action UserMsg_VGUIMenu(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init) {
	//message structure:
	// <string:name><byte:visible><byte:numkeys>[<string:key><string:value>]*
	char panel[12];
	msg.ReadString(panel, sizeof(panel));
	bool hidden = !msg.ReadByte();
	int count = msg.ReadByte();
	
	char buf[192];
	char buf2[10];
	int flags=0; //if this is one of our motd messages, flags will be 2
	for (int i; i<count; i++) {
		msg.ReadString(buf2, sizeof(buf2));
		msg.ReadString(buf, sizeof(buf));
		
		if (strcmp(buf2,"cmd")==0 && strcmp(buf,"5")==0) flags++;
		else if (strcmp(buf2,"type")==0 && strcmp(buf,"2")==0) flags++;
		else if (strcmp(buf2,"msg")==0 && StrContains(buf,g_motdmenuwwwbase)==0) flags++;
	}
	
	bool otherPanelIsMotd = strcmp(panel,"info")==0;
	bool nonMotdOpened = (!otherPanelIsMotd && !hidden);
	bool motdIsMenu = otherPanelIsMotd && flags == 3;
	if (nonMotdOpened || !motdIsMenu) {
		//some other panel opened, or the info pannel was hidden -> deactivate motd menu
//		if (nonMotdOpened) PrintToServer("[MotdMenu] Non-Motd VGUI panel was opened");
//		if (!motdIsMenu) {
//			if (hidden) PrintToServer("[MotdMenu] Some Motd was force closed");
//			else PrintToServer("[MotdMenu] Non-Menu Motd was opened");
//		}
		for (int i;i<playersNum;i++) {
			Impl_CancelMotdMenu(players[i], _, MenuCancel_Interrupted);
		}
	}
	return Plugin_Continue;
}

public Action Event_ClosedHtmlpage(int client, const char[] command, int argc) {
	Impl_CancelMotdMenu(client, _, MenuCancel_Exit);
	return Plugin_Continue;
}

/**
 * This call is for menu action proxied through the motd
 */
void MenuActionIndirect(SMenuExtra mex, MenuAction action, int param1, int param2) {
	if (!(mex.filter & action)) return; //action was not subscribed to
	//perform primary action
	Call_StartFunction(mex.owner, mex.callback);
	Call_PushCell(mex.handle);
	Call_PushCell(action);
	Call_PushCell(param1);
	Call_PushCell(param2);
	Call_Finish();
	//if a menu is cancelled/interacted with, it usually ends afterwards
	bool menuEnded, playSound;
	int endReason, endP2;
	//determin the proper menu end action and context to play for this action (if any)
	playSound = (!(mex.handle.OptionFlags & MENUFLAG_NO_SOUND));
	switch (action) {
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_Exit) {
				if (playSound) EmitSoundToClient(param1, g_coreMenuSoundExit);
				endReason = MenuEnd_Exit;
			} else if (param2 == MenuCancel_ExitBack) {
				if (playSound) EmitSoundToClient(param1, g_coreMenuSoundExitBack);
				endReason = MenuEnd_ExitBack;
			} else {
				endReason = MenuEnd_Cancelled;
				endP2 = param2;
			}
			menuEnded = true;
		}
		case MenuAction_Select: {
			if (playSound) EmitSoundToClient(param1, g_coreMenuSoundSelect);
			endReason = MenuEnd_Selected;
			menuEnded = true;
		}
	}
	//if the action ended the menu, play that message as well
	if (menuEnded) {
		Call_StartFunction(mex.owner, mex.callback);
		Call_PushCell(mex.handle);
		Call_PushCell(MenuAction_End);
		Call_PushCell(endReason);
		Call_PushCell(endP2);
		Call_Finish();
	}
}
/**
 * This is required for menus that are not displayed as motd.
 * Since we own the menu now, we have to own the handler, so we pipe the call back manually
 */
public int ProxyMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	SMenuExtra mex;
	// probably not shown as motd
	if (FindMenuExtra(menu, mex)==-1) {
		ThrowError("F*** - The menu is gone...");
		return 0;
	}
	Call_StartFunction(mex.owner, mex.callback);
	Call_PushCell(menu);
	Call_PushCell(mex.filter & action);
	Call_PushCell(param1);
	Call_PushCell(param2);
	int returnlol;
	Call_Finish(returnlol);
	return returnlol;
}

static void Impl_CancelMotdMenu(int client, bool closePanel=false, int exitcancelreson=0) {
	if (clientIgnorePanelsClosing[client]) return;
	if (clientActiveMotdMenu[client] != INVALID_HANDLE) {
		if (exitcancelreson) {
			SMenuExtra mex;
			if (FindMenuExtra(clientActiveMotdMenu[client], mex)!=-1) {
				MenuActionIndirect(mex, MenuAction_End, MenuEnd_Cancelled, exitcancelreson);
			}
		}
		clientActiveMotdMenu[client] = null;
		if (closePanel) CloseMOTDPanel(client);
		NukeEntries(client);
	}
}
static void CloseMOTDPanel(int client) {
	if (!Client_IsValid(client)) return;
	ShowVGUIPanel(client, "info", _, false);
}
static void ShowMOTDPanelEx(int client, const char[] title, const char[] msg, int motdpanel_type, int cmd = Cmd_None, bool big=false) {
	KeyValues kv = new KeyValues("data");
	kv.SetString("title", title);
	kv.SetNum("type", motdpanel_type);
	kv.SetString("msg", msg);
	if (g_bEngineIsTF2 && big) kv.SetNum("customsvr", 1);
	kv.SetNum("cmd", cmd);
	ShowVGUIPanel(client, "info", kv);
}

public Action Timer_UpdateClientHtmlMotd(Handle timer) {
	static int client;
	bool loopBreaker;
	do {
		if (++client > MaxClients) {
			client=1;
			if (loopBreaker) return;
			else loopBreaker =! loopBreaker;
		}
	} while (!Client_IsIngame(client) || IsFakeClient(client) || IsClientSourceTV(client));
	
	QueryClientConVar(client, "cl_disablehtmlmotd", Await_ClientConvar_Disablehtmlmotd);
}

public void Await_ClientConvar_Disablehtmlmotd(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue) {
	g_clientDisablehtmlmotd[client] = (result != ConVarQuery_Okay || !!StringToInt(cvarValue));
}

public void Await_DatabaseConnected(Database db, const char[] error, any data) {
	if (g_database != INVALID_HANDLE) {
		delete g_database;
	}
	//invalidate old menu handlers
	for (int i=0;i<=MAXPLAYERS;i++) {
		Impl_CancelMotdMenu(i,true,MenuCancel_Interrupted);
	}
	if (db != INVALID_HANDLE) {
		db.SetCharset("utf8mb4");
		g_database = db;
		g_bDBconnected = true;
		
		SQL_EscapeString(db, g_serverId, g_dbserverId, sizeof(g_dbserverId));
		
		RequestFrame(CreateTables);
	} else {
		if (strlen(error)) {
			SetFailState("[MotdMenu] Database error: %s", error);
		} else {
			SetFailState("[MotdMenu] Unable to connect to database");
		}
	}
}

void CreateTables() {
	g_database.Query(Await_QueryError, "CREATE TABLE IF NOT EXISTS motdmenu_itemdef ("
	..."`serverid` VARCHAR(16) NOT NULL,"
	..."`menuid` VARCHAR(10) NOT NULL," //prevents guessing
	..."`client` TINYINT NOT NULL,"
	..."`item` INT DEFAULT NULL,"
	..."`info` VARCHAR(64) DEFAULT NULL,"
	..."`value1` VARCHAR(256) NOT NULL,"
	..."`value2` VARCHAR(256) DEFAULT NULL,"
	..."`flags` INT NOT NULL,"
	..."`timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
//	..."PRIMARY KEY (`serverid`,`menuid`,`client`,`item`)"
	...") CHARACTER SET utf8mb4");
}

void NukeEntries(int client=0) {
	if (g_bDBconnected && strlen(g_dbserverId) && g_database != INVALID_HANDLE) {
		if (!client) {
			QueryFormat(Await_QueryError, _,_, "DELETE FROM motdmenu_itemdef WHERE `serverid`='%s' OR TIMESTAMPDIFF(MINUTE, `timestamp`, NOW())>60", g_dbserverId);
		} else {
			QueryFormat(Await_QueryError, _,_, "DELETE FROM motdmenu_itemdef WHERE `serverid`='%s' AND `client`=%i", g_dbserverId, GetClientUserId(client));
		}
	}
}

public void Await_QueryError(Database db, DBResultSet results, const char[] error, any data) {
	if (results == null) {
		if (strlen(error))
			PrintToServer("Database Error: %s", error);
		else
			PrintToServer("Unknown Database Error!");
	}
}

static bool InvokeIconProvider(Handle plugin, MotdIconPathProvider provider, const char[] info, char[] icon, int cap) {
	if (provider == INVALID_FUNCTION) return false;
	Call_StartFunction(plugin, provider);
	Call_PushString(info);
	Call_PushStringEx(icon, cap, SM_PARAM_STRING_UTF8, SM_PARAM_COPYBACK);
	Call_PushCell(cap);
	bool result = (Call_Finish(result)==SP_ERROR_NONE) && result;
	return result;
}

static void AddQueryTx(Transaction tax, const char[] format, any...) {
	char formatBuf[1024];
	VFormat(formatBuf, sizeof(formatBuf), format, 3);
	tax.AddQuery(formatBuf);
}
static void QueryFormat(SQLQueryCallback callback, any data=0, DBPriority priority=DBPrio_Normal, const char[] format, any...) {
	char formatBuf[1024];
	VFormat(formatBuf, sizeof(formatBuf), format, 5);
	g_database.Query(callback, formatBuf, data, priority);
}

static int FindMenuExtra(Menu search, SMenuExtra data) {
	int at = MenuExtra.FindValue(search);
	if (at != -1) {
		MenuExtra.GetArray(at,data,sizeof(SMenuExtra));
	}
	return at;
}

static char base64chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
//url safe version
static void base64enc(const char[] data, char[] out, int outsz, int datasz=0) {
	//i don't like smlibs implementation :D
	int accu = 0;
	int bitcnt = 0;
	int outpos = 0;
	int shift = 2;
	//calulcate size requirement
	if (datasz <= 0)
		datasz = strlen(data);
	accu = 4*RoundToCeil(datasz/3.0)+1;
	if (outsz < accu)
		ThrowError("Output buffer not big enough");
	accu = 0;
	
	for (int i; i<datasz; i++) {
		accu <<= 8;
		accu |= (data[i] & 0xff);
		bitcnt += 8;
		while (bitcnt >= 6) {
			int value = (accu >> shift) & 0x3f;
			if (shift == 6) shift = 0; else shift += 2;
			out[outpos] = base64chars[value];
			outpos++;
			bitcnt-=6;
		}
	}
	if (bitcnt > 0) {
		//push zeros until we have 6 bits
		accu <<= (6-bitcnt);
		out[outpos] = base64chars[accu&0x3f];
		outpos++;
	}
	while ((outpos%4) != 0) {
		//padding
		out[outpos] = '.';
		outpos++;
	}
	out[outpos] = 0;
}
static void base64encint(int value, char[] out, int outsz) {
	char bytes[4];
	bytes[0] = (value >> 24) & 0xff;
	bytes[1] = (value >> 16) & 0xff;
	bytes[2] = (value >>  8) & 0xff;
	bytes[3] = (value >>  0) & 0xff;
	base64enc(bytes, out, outsz, 4);
}

// --== COOKIES ==--

public void OnClientCookiesCached(int client) {
	Handle cookie;
	char buffer[2];
	if ((cookie=FindClientCookie(COOKIE_ENABLED)) != INVALID_HANDLE) {
		GetClientCookie(client, cookie, buffer, sizeof(buffer));
		g_clientDisablemotdmenu[client] = !StringToInt(buffer);
	} else g_clientDisablemotdmenu[client] = false;
	if ((cookie=FindClientCookie(COOKIE_BIGMOTD)) != INVALID_HANDLE) {
		GetClientCookie(client, cookie, buffer, sizeof(buffer));
		g_clientMotdSwitchBig[client] = !!StringToInt(buffer);
	} else g_clientMotdSwitchBig[client] = false;
}

public void cookieMenuHandler(int client, CookieMenuAction action, any info, char[] buffer, int maxlen) {
	if(action == CookieMenuAction_SelectOption) {
		showSettingsMenu(client);
	}
}

void showSettingsMenu(int client) {
	Menu menu = new Menu(settingsMenuActionHandler);
	menu.SetTitle("Motd Menus");
	if (g_clientDisablemotdmenu[client]||g_clientDisablehtmlmotd[client]) {
		menu.AddItem("", "[Disabled]", ITEMDRAW_DISABLED);
	} else {
		menu.AddItem("", "[Enabled]", ITEMDRAW_DISABLED);
	}
	if (g_clientDisablemotdmenu[client]) {
		menu.AddItem("1", "Turn On");
	} else {
		menu.AddItem("1", "Turn Off");
	}
	if (g_clientMotdSwitchBig[client]) {
		menu.AddItem("2", "Big Motd");
	} else {
		menu.AddItem("2", "Small Motd");
	}
	if (g_clientDisablehtmlmotd[client]) {
		menu.AddItem("","",ITEMDRAW_SPACER);
		menu.AddItem("","HTML MOTDs are disabled", ITEMDRAW_DISABLED);
	}
	menu.ExitBackButton = true;
	menu.Display(client, 30);
}

public int settingsMenuActionHandler(Menu menu, MenuAction action, int param1, int param2) {
	if(action == MenuAction_Select) {
		char val[2] = "1";
		char info[2];
		Handle cookie;
		
		menu.GetItem(param2, info, sizeof(info));
		if (strcmp(info,"1")==0) {
			g_clientDisablemotdmenu[param1] =! g_clientDisablemotdmenu[param1];
			if (g_clientDisablemotdmenu[param1]) val[0] = '0';
			if((cookie = FindClientCookie(COOKIE_ENABLED)) != null) {
				SetClientCookie(param1, cookie, val);
			}
		} else if (strcmp(info,"2")==0) {
			g_clientMotdSwitchBig[param1] =! g_clientMotdSwitchBig[param1];
			if (!g_clientMotdSwitchBig[param1]) val[0] = '0';
			if((cookie = FindClientCookie(COOKIE_BIGMOTD)) != null) {
				SetClientCookie(param1, cookie, val);
			}
		}
		
		showSettingsMenu(param1);
	} else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
		ShowCookieMenu(param1);
	} else if(action == MenuAction_End) {
		delete menu;
	}
}

// --== NATIVES ==--

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("CreateMotdMenu", Native_CreateMotdMenu);
	CreateNative("CloseMotdMenu", Native_CloseMotdMenu);
	CreateNative("DisplayMotdMenu", Native_DisplayMotdMenu);
	CreateNative("CancelMotdMenu", Native_CancelMotdMenu);
	CreateNative("Client_CheckMotdMenu", Native_CheckMotdMenu);
	CreateNative("CloseAllMenus", Native_CloseAllMenus);
	RegPluginLibrary("motdmenu");
	return APLRes_Success;
}

public any Native_CreateMotdMenu(Handle plugin, int argc) {
	MenuHandler callback = view_as<MenuHandler>(GetNativeFunction(1));
	MenuAction filter = view_as<MenuAction>(GetNativeCell(2));
	SMenuExtra mex;
	
	//menus are not cloneable
	mex.owner = plugin;
	mex.callback = callback;
	mex.filter = filter;
	mex.handle = CreateMenu(ProxyMenuHandler, filter);
	
	MenuExtra.PushArray(mex, sizeof(SMenuExtra));
	return view_as<MotdMenu>(mex.handle);
}

public any Native_DisplayMotdMenu(Handle plugin, int argc) {
	Menu menu = view_as<Menu>(GetNativeCell(1));
	int client = view_as<int>(GetNativeCell(2));
	MotdIconPathProvider icons = view_as<MotdIconPathProvider>(GetNativeFunction(3));
	SMenuExtra mex;
	
	if (!Client_IsIngame(client)) ThrowNativeError(SP_ERROR_PARAM, "Invalid client");
	if (g_clientDisablehtmlmotd[client] || g_clientDisablemotdmenu[client]) return false;
	if (FindMenuExtra(menu,mex)==-1) ThrowNativeError(SP_ERROR_PARAM, "The menu was not registered with motd menu");
	if (!g_bDBconnected) ThrowNativeError(SP_ERROR_NATIVE, "MOTD Menu is not connected to a database");
	
	char bufInfo[64], bufVal1[256], bufVal2[256], buffer[256], buffer2[64];
	int style;
	char menuid[9]; //theoretically needs checking for collisions
	base64encint(((GetRandomInt(0,0xffff)<<16)|GetRandomInt(0,0xffff)), menuid, sizeof(menuid));
	
	Transaction tx = SQL_CreateTransaction();
	AddQueryTx(tx, "DELETE FROM motdmenu_itemdef WHERE `serverid`='%s' AND `client`=%i", g_dbserverId, GetClientUserId(client));
	
	menu.GetTitle(buffer, sizeof(buffer));
	SQL_EscapeString(g_database, buffer, bufVal1, sizeof(bufVal1));
	//inject translations for auto buttons :)
	SetGlobalTransTarget(client);
	Format(buffer, sizeof(buffer), "%t;%t", "Back", "Exit");
	SQL_EscapeString(g_database, buffer, bufVal2, sizeof(bufVal2));
	
	AddQueryTx(tx, "INSERT INTO motdmenu_itemdef (`serverid`,`menuid`,`client`,`info`,`value1`,`value2`,`flags`) VALUES ('%s','%s',%i,'%s','%s','%s',%i)",
		g_dbserverId, menuid, GetClientUserId(client), MOTDMENU_VERSION, bufVal1, bufVal2, menu.OptionFlags);
	
	for (int i;i<menu.ItemCount;i++) {
		style=0;
		menu.GetItem(i, buffer2, sizeof(buffer2), style, buffer, sizeof(buffer));
		SQL_EscapeString(g_database, buffer2, bufInfo, sizeof(bufInfo));
		SQL_EscapeString(g_database, buffer, bufVal1, sizeof(bufVal1));
		if (InvokeIconProvider(mex.owner, icons, buffer2, buffer, sizeof(buffer))) {
			SQL_EscapeString(g_database, buffer, bufVal2, sizeof(bufVal2));
			AddQueryTx(tx, "INSERT INTO motdmenu_itemdef (`serverid`,`menuid`,`client`,`item`,`info`,`value1`,`value2`,`flags`) VALUES ('%s','%s',%i,%i,'%s','%s','%s',%i)",
				g_dbserverId, menuid, GetClientUserId(client), i, bufInfo, bufVal1, bufVal2, style);
		} else {
			AddQueryTx(tx, "INSERT INTO motdmenu_itemdef (`serverid`,`menuid`,`client`,`item`,`info`,`value1`,`flags`) VALUES ('%s','%s',%i,%i,'%s','%s',%i)",
				g_dbserverId, menuid, GetClientUserId(client), i, bufInfo, bufVal1, style);
		}
	}
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(menuid);
	pack.WriteCell(menu);
	pack.Reset();
	g_database.Execute(tx, Await_MenuInsertQuerySuccess, Await_MenuInsertQueryFailed, pack);
	return true;
}

public void Await_MenuInsertQuerySuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData) {
	DataPack pack = view_as<DataPack>(data);
	int userId;
	char menuid[9];
	char buffer[192];
	userId = pack.ReadCell();
	int client = GetClientOfUserId(userId);
	pack.ReadString(menuid,sizeof(menuid));
	clientActiveMotdMenu[client] = view_as<Menu>( pack.ReadCell() );
	Format(buffer, sizeof(buffer), "%s/menu.php?s=%s&m=%s&c=%i", g_motdmenuwwwbase, g_serverId, menuid, userId);
	ShowMOTDPanelEx(client, "MoMe", buffer, MOTDPANEL_TYPE_URL, Cmd_ClosedHTMLPage, g_clientMotdSwitchBig[client]);
	delete pack;
}

public void Await_MenuInsertQueryFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	PrintToServer("Failed to insert Menu into database at %i: %s", failIndex, error);
	delete view_as<DataPack>(data);
}

static void Impl_CloseMotdMenu(Menu menu, bool deleteit) {
	int at = MenuExtra.FindValue(menu);
	if (at < 0) {
		menu.Cancel();
		delete menu;
		return;
	}
	//ThrowNativeError(SP_ERROR_PARAM, "The menu was not created with motd menu");
	
	//cancel
	for (int i=1;i<=MAXPLAYERS;i++) {
		if (clientActiveMotdMenu[i] == menu) Impl_CancelMotdMenu(i);
	}
	menu.Cancel();
	//free
	if (deleteit) {
		delete menu;
		MenuExtra.Erase(at);
	}
}
public any Native_CancelMotdMenu(Handle plugin, int argc) {
	Menu menu = view_as<Menu>(GetNativeCell(1));
	Impl_CloseMotdMenu(menu, false);
}
public any Native_CloseMotdMenu(Handle plugin, int argc) {
	Menu menu = view_as<Menu>(GetNativeCellRef(1));
	Impl_CloseMotdMenu(menu, true);
	SetNativeCellRef(1, INVALID_HANDLE);
}

public any Native_CheckMotdMenu(Handle plugin, int args) {
	int client = GetNativeCell(1);
	if (!Client_IsValid(client)) ThrowNativeError(SP_ERROR_INDEX, "Invalid client index %i", client);
	return !g_clientDisablemotdmenu[client] && !g_clientDisablehtmlmotd[client];
}

public any Native_CloseAllMenus(Handle plugin, int args) {
	SMenuExtra mex;
	for (int i = MenuExtra.Length-1; i >= 0; i--) {
		MenuExtra.GetArray(i, mex, sizeof(SMenuExtra));
		if (mex.owner != plugin) continue;
		for (int c=1;c<MaxClients;i++)
			if (clientActiveMotdMenu[c]==mex.handle) {
				clientActiveMotdMenu[c]=null;
				CloseMOTDPanel(c);
			}
		delete mex.handle;
		MenuExtra.Erase(i);
	}
}