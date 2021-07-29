<?php /* PROCESSING */
	
	require 'settings.php';
	require 'rcon_code.php';

	$menuTitle = 'MOTD Menu';
	$supprtedPluginVersions = [ '21w26b','21w26c','21w30a' ];
	
	//static data - taken from source mod 'menus.inc'

	// i choose to not do votes, feel free to add the stuff needed for that

	$MenuAction_Start  = (1<<0);     /**< A menu has been started (nothing passed) */
	$MenuAction_Select = (1<<2);     /**< An item was selected (param1=client, param2=item) */
	$MenuAction_Cancel = (1<<3);     /**< The menu was cancelled (param1=client, param2=reason) */
	$MenuAction_End    = (1<<4);     /**< A menu display has fully ended.
                                         param1 is the MenuEnd reason, and if it's MenuEnd_Cancelled, then
                                         param2 is the MenuCancel reason from MenuAction_Cancel. */
	//we cannot support other actions
	
	$ITEMDRAW_DEFAULT   =        (0);     /**< Item should be drawn normally */
	$ITEMDRAW_DISABLED  =        (1<<0);  /**< Item is drawn but not selectable */
	$ITEMDRAW_RAWLINE   =        (1<<1);  /**< Item should be a raw line, without a slot */
	$ITEMDRAW_NOTEXT    =        (1<<2);  /**< No text should be drawn */
	$ITEMDRAW_SPACER    =        (1<<3);  /**< Item should be drawn as a spacer, if possible */
	$ITEMDRAW_IGNORE    =((1<<1)|(1<<2)); /**< Item should be completely ignored (rawline + notext) */
	$ITEMDRAW_CONTROL   =        (1<<4);  /**< Item is control text (back/next/exit) */

	$MENUFLAG_BUTTON_EXIT      = (1<<0);  /**< Menu has an "exit" button (default if paginated) */
	$MENUFLAG_BUTTON_EXITBACK  = (1<<1);  /**< Menu has an "exit back" button */
	
	$MenuCancel_Disconnected = -1;   /**< Client dropped from the server */
	$MenuCancel_Interrupted  = -2;   /**< Client was interrupted with another menu */
	$MenuCancel_Exit         = -3;   /**< Client exited via "exit" */
	$MenuCancel_NoDisplay    = -4;   /**< Menu could not be displayed to the client */
	$MenuCancel_Timeout      = -5;   /**< Menu timed out */
	$MenuCancel_ExitBack     = -6;   /**< Client selected "exit back" on a paginated menu */
	
	$MenuEnd_Selected   = 0;        /**< Menu item was selected */
	$MenuEnd_Cancelled  = -3;       /**< Menu was cancelled (reason in param2) */
	$MenuEnd_Exit       = -4;       /**< Menu was cleanly exited via "exit" */
	$MenuEnd_ExitBack   = -5;       /**< Menu was cleanly exited via "back" */
	
	ob_start();
	
	//connect to db
	$sql = new mysqli(
		$settings['database']['host'], 
		$settings['database']['user'], 
		$settings['database']['pass'], 
		$settings['database']['database'], 
		isset($settings['database']['port']) ? $settings['database']['port'] : ini_get("mysqli.default_port")
		);
	if (!$sql) goto end;
	$sql->set_charset('utf8mb4');
	
	function retag(&$wasOpen) {
		if ($wasOpen) { ?></p><? }
		else $wasOpen = true;
		?><p><?
	}
	function actionquery($action, $param1=0, $param2=0) {
		return '?s='.$_GET['s'].'&m='.$_GET['m'].'&c='.$_GET['c']."&a=$action&p1=$param1&p2=$param2";
	}
	function actionrcon($action, $param1=0, $param2=0) {
		global $settings;
		if (!isset($settings['servers'][$_GET['s']])) return false;
		$usr = intval($_GET['c']);
		$sid = $_GET['s'];
		$sv = $settings['servers'][$_GET['s']];
		$command = "sm_motdmenu_callback $sid $usr $action $param1 $param2";
		$rcon = new srcds_rcon();
		return ($rcon->rcon_command($sv['host'],$sv['port'],$sv['rconpass'], $command) !== false);
	}
	if (strpos($_SERVER['HTTP_USER_AGENT'],' Valve Client/')===false) {
		http_response_code(403);
		die();
	}
	
	//validate first part of data
	if (empty($_GET['s']) || empty($_GET['m']) || empty($_GET['c'])) {
		?><h1>Unauthorized</h1><p>You shall not pass!</p><?
		goto end;
	}
	if (!isset($settings['servers'][$_GET['s']])) {
		?><h1>Could not find server <?=$_GET['s']?></h1><p>Please Check your config files</p><?
		goto end;
	}
	$sv = $sql->real_escape_string($_GET['s']);
	$mi = $sql->real_escape_string($_GET['m']);
	$ci = intval($_GET['c']);
	$sname = $settings['servers'][$sv]['name'];
	if (!preg_match('/^\w+$/',$sv) || !preg_match('/^[\w-]+\.{0,2}$/', $mi) || $ci < 1) {
		?><h1>Bad Request</h1><p>I don't know what you did, but there's no menu here</p><?
		goto end;
	}
	
	if (!empty($_GET['a'])) {
		//is action, get params
		if (!is_numeric($_GET['a'])) {
			?><h1>...</h1><p>#NnA</p><?
			goto end;
		}
		$a = intval($_GET['a']);
		$p1 = 0;
		$p2 = 0;
		if (!empty($_GET['p1'])) {
			if (!is_numeric($_GET['p1'])) {
				?><h1>...</h1><p>#Nnp</p><?
				goto end;
			}
			$p1 = intval($_GET['p1']);
		}
		if (!empty($_GET['p2'])) {
			if (!is_numeric($_GET['p2'])) {
				?><h1>...</h1><p>#NnP</p><?
				goto end;
			}
			$p2 = intval($_GET['p2']);
		}
		if (!actionrcon($a,$p1,$p2)) {
			?><h1>...</h1><p>#rcA</p><?
			goto end;
		}
	} else {
		if (!actionrcon($MenuAction_Start)) {
			?><h1>...</h1><p>#Arc</p><?
			goto end;
		}
		//is not an action
		$result = $sql->query("SELECT `item`,`info`,`value1`,`value2`,`flags` FROM motdmenu_itemdef WHERE `serverid`='$sv' AND `menuid`='$mi' AND `client`=$ci ORDER BY `item` ASC");
		$menuFlags = 0;
		$menuButtons = [];
		$motdMenuPluginVersion;
		$items = [];
		if ($result) while (($row = $result->fetch_assoc())!==NULL) {
			if (is_null($row['item'])) { //header
				$menuTitle = $row['value1'];
				$menuFlags = $row['flags'];
				$menuButtons = explode(';', $row['value2']); //translations: back;exit
				$motdMenuPluginVersion = $row['info'];
			} else {
				$items[] = [
					'item'=>$row['item'],
					'info'=>$row['info'],
					'display'=>$row['value1'],
					'icon'=>$row['value2'],
					'style'=>$row['flags'],
				];
			}
		}
		?><small><?=$sname?></small><h1><?=$menuTitle?></h1><?
		if (!isset($motdMenuPluginVersion)) {
			?><b>Something went wrong, please try again.</b><?
			goto end;
		}
		if (!in_array($motdMenuPluginVersion, $supprtedPluginVersions)) {
			?><b>The web version of Motd Menu does not support plugin version <?=$motdMenuPluginVersion?></b><?
			goto end;
		}
		$popen=false;
		$inListing = false;
		foreach ($items as $item) {
			if (($item['style'] & $ITEMDRAW_IGNORE)==$ITEMDRAW_IGNORE) continue;
			if (($item['style'] & $ITEMDRAW_CONTROL)==$ITEMDRAW_CONTROL) continue; //we don't need those explicitly
			if (($item['style'] & $ITEMDRAW_SPACER)==$ITEMDRAW_SPACER) {
				retag($popen);
				continue;
			}
			$text = (($item['style'] & $ITEMDRAW_NOTEXT)==$ITEMDRAW_NOTEXT) ? "" : $item['display'];
			if (($item['style'] & $ITEMDRAW_RAWLINE)==$ITEMDRAW_RAWLINE) {
				retag($popen);
				if (!is_null($item['icon'])) {
					?><img src="<?=$item['icon']?>"/><br><?
					if (!empty($text)) { ?><br><? }
				}
				echo $text;
				$inListing = false;
			}
			if (!$inListing) { retag($popen); $inListing = true; }
			if (($item['style'] & $ITEMDRAW_DISABLED)==$ITEMDRAW_DISABLED) {
				?><span class="menuitem"><?
				if (!is_null($item['icon'])) {
					?><img src="<?=$item['icon']?>"/><?
					if (!empty($text)) { ?><br><? }
				}
				echo $text;
				?></span><?
			} else {
				?><a class="menuitem" href="<?=actionquery($MenuAction_Select,$ci,$item['item'])?>"><?
				if (!is_null($item['icon'])) {
					?><img src="<?=$item['icon']?>"/><?
					if (!empty($text)) { ?><br><? }
				}
				echo $text;
				?></a><?
			}
		}
		?></p><p class="rightalign"><?
			if (($menuFlags & $MENUFLAG_BUTTON_EXIT)==$MENUFLAG_BUTTON_EXIT) {
				?><a class="menuitem" href="<?=actionquery($MenuAction_Cancel,$ci,$MenuCancel_Exit)?>"><?=$menuButtons[1]?></a><?
			}
			if (($menuFlags & $MENUFLAG_BUTTON_EXITBACK)==$MENUFLAG_BUTTON_EXITBACK) {
				?><a class="menuitem" href="<?=actionquery($MenuAction_Cancel,$ci,$MenuCancel_ExitBack)?>"><?=$menuButtons[0]?></a><?
			}
		?></p><?
	}

end: //alternative would be a giant try catch with no other benefits
	$content = ob_get_contents();
	ob_end_clean();
	
?><!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" 
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
	<head>
		<meta http-equiv="Content-Type" content="text/html;charset=utf-8"/>
		<title><?= $menuTitle ?></title>
		<link rel="stylesheet" href="styles.css">
	</head>

	<body>
		<?= $content ?>
	</body>
</html>