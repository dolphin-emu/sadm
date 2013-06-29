<?php

define('MEDIAWIKI', 1);
$wgDBtype           = "pgsql";
$wgDBserver         = "postgresql1.alwaysdata.com";
$wgDBname           = "dolphin-emu_wiki";
$wgDBuser           = "dolphin-emu_wiki";
$wgDBpassword       = "";
$wgDBprefix         = "";
$wgDBTableOptions   = "";

if (!isset($_GET['gameid']) || strlen($_GET['gameid']) != 6)
{
	header('Location: /');
	exit;
}

$dbh = new PDO("$wgDBtype:host=$wgDBserver;dbname=$wgDBname", $wgDBuser, $wgDBpassword);

$gameid = $_GET['gameid'];
$re = $gameid[0] . $gameid[1] . $gameid[2] . "[A-Z]" . $gameid[4] . $gameid[5];

$stmt = $dbh->prepare("SELECT page_title FROM page WHERE page_title REGEXP ? AND page_is_redirect = 1");
$stmt->bindParam(1, $re, PDO::PARAM_STR);
$stmt->execute();

$res = NULL;
$arr = $stmt->fetchAll();
foreach ($arr as $row)
{
	$res = $row['page_title'];
	if ($row['page_title'] == $gameid)
		break;
}

if (!$res)
{
	// Did not find a redirect
	$res = $gameid;

	$stmt = $dbh->prepare("INSERT INTO missing_redirects(gameid, count) VALUES (?, 1) ON DUPLICATE KEY UPDATE count=count+1");
	$stmt->bindParam(1, $gameid, PDO::PARAM_STR);
	$stmt->execute();
}

header("Location: /index.php?title=$res");
exit;
