# Gate SQL

The plugin creates a table in the MySQL database to store player names linked to Steam ID or IP address.

## Features

Thanks to the flexible settings that are applied during the build of the plugin, it can be built for any of your needs:

* Uploading your own configuration file or from sql.cfg to connect to MySQL.
* Loading your own kvars or existing ones from gate sql.cfg to connect to MySQL.
* Recording or updating the player's name as soon as he logs in to the server.
* Record or update the player's name as soon as he changes the name.
* Read and change the player's name if the name differs from the last entry.
* Blocking the message "player changed name to".
* Blocking the nickname change during the game.
* Checking by: SteamID, IP, SteamID and IP, SteamID or IP.

## Requirements

* Version amxmodx 1.8.3 (1.9.0).
* ReHLDS (ReAPI) only.

## Installation

* Configure plugin definitions according to your needs.
* Build the plugin with a compiler and move it to the **plugins** section.
* Write in the **plugins.cfg** file the name of the plugin at the very top after the standard plugins **amxmodx**.
