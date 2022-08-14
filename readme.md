# Gate SQL

The plugin creates a table in the MySQL database to store player names linked to Steam ID or IP address.

## Features

Thanks to the flexible settings that are applied during the build of the plugin, it can be built for any of your needs:

* Load your own configuration file or from sql.cfg to connect to MySQL.
* Upload your own cvars or existing cvars from sql.cfg to connect to MySQL.

* Record or update the player's name as soon as he enters the server.

* Record or update the player's name as soon as he changes the name.

* Read and change the player's name if the name is different from the last entry.

* Deleting a player from the server if the name differs from the previous entry.

* Blocking the message "player changed name to".

* Blocking the change of nickname during the game.

* Check by SteamID or by IP.

## Requirements

* Version amxmodx 1.8.3 (1.9.0).
* ReHLDS (ReAPI) only.

## Installation

* Configure plugin definitions according to your needs.
* Build the plugin with a compiler and move it to the **plugins** section.
* Write in the **plugins.cfg** file the name of the plugin at the very top after the standard plugins **amxmodx**.
