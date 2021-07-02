<?php
//if the sys admin forgets to hide this file, this php will at least not leak config if accessed through apache
$settings = [
	"database" => [
		"host"		=>	"localhost",
		"database"	=>	"default",
		"user"		=>	"root",
		"pass"		=>	"",
		//"port"	=>	"0",
	],
	"servers" => [
		// names should be unique. the MOTD needs this to know what server to rcon back to
		"srvid1" => [
			"name"    => "My Fancy Server",
			"host"    => "192.168.2.187",
			"port"    => "27015",
			"rconpass"=> "hunter42",
		],
	],
];