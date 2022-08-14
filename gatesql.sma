/**
 * Binds the name to the IP address of the player and returns the saved nickname if the player has changed it.
 * Plugin records the name, IP address and Steam ID that can be used to fully identify the player.
 *
 * It does not provide for the possibility of changing the name and is an extension for the website.
 * Does not work with bots and HLTV.
 */

#include <amxmodx>
#include <reapi>
#include <sqlx>

#define PLUGIN "Gates SQL"
#define AUTHOR "Clay Whitelytning"
#define VERSION "1.0.0"

/**
 * Allows you to use the connection settings from sql.ini.
 * This is necessary first of all so as not to produce settings for the sake of connection that are already specified somewhere.
 * If not defined, custom cvars and a configuration file will be used.
 * 
 * Note that logins_sql_table must be specified 
 * for example in amxx.cfg in order to use a different table name.
 */
#define USE_SQL_CFG

/**
 * If the USE_SQL_CFG define is used, then you do not need to use your own configuration.
 * However, if sql.ini is not loaded by default, you can use it.
 * 
 * If the SQL_CFG definition is not used, 
 * uncomment to load your own configuration file.
 */
//#define USE_FORCE_LOAD_CONFIG

/**
 * As a rule, it is difficult to hide the address if a VPN is not used.
 * If you do not allow entry from one IP of several players, leave it.
 * Comment if you want to use STEAM ID to identify the player.
 */
#define USE_IP_FOR_IDENTITY

/**
 * Defines the processing of the player when entering the server.
 */
#define USE_CLIENT_PUT_IN_SERVER

/**
 * If determined, the player will be kicked with the reason specified in the logins_kick_reason cvar.
 * Check is case-sensitive and any mismatch of letters will lead to the removal of the player from the server.
 * If commented out the nickname will be changed will be forced. 
 * Player will be kicked only when entering the server.
 */
//#define USE_KICK_PLAYER

/**
 * Reads and changes the player's nickname 
 * (if it does not match or the player has not logged in for the first time).
 */
#define USE_CHANGE_NAME_ON_PUT_IN_SERVER

/**
 * Regardless of whether a player has been recorded or not,
 * this definition will record his name, thereby updating or creating a new record.
 */
#define USE_WRITE_NAME_ON_PUT_IN_SERVER

/**
 * Allows you to catch changes in the player's name.
 * If defined, saving will be performed when changing the name.
 */
#define USE_HOOK_SET_CLIENT_USER_INFO_NAME

/**
 * If there is no need to display a message that the player has changed the name, 
 * use this definition (hook to catch the name change must be defined).
 */
#define USE_BLOCK_MESSAGE_ON_CHANGE_NAME

/**
 * This definition blocks name changes during the game
 * (hook to catch the name change must be defined).
 */
#define USE_BLOCK_CHANGE_NAME_IN_GAME

/**
 * Other settings that are better not to touch 
 * if you don't know what they will lead to after the change.
 */
#define SQL_DATA_SIZE 33
#define DATA_SIZE 256
#define STEAMID_SIZE 35
#define NAME_SIZE 33
#define IP_SIZE 23

/**
 * --------------------------------------------------------------------------------------
 * Implementation
 * --------------------------------------------------------------------------------------
 */
#define is_player(%1) !is_user_bot(%1) && !is_user_hltv(%1)

#if defined USE_KICK_PLAYER
new cvar_kick_reason;
#endif

#if defined USE_BLOCK_CHANGE_NAME_IN_GAME
new players[MAX_PLAYERS + 1];
#endif

#if defined USE_BLOCK_MESSAGE_ON_CHANGE_NAME
new message_say_text;
#endif

new cvar_sql_host, 
	cvar_sql_user, 
	cvar_sql_pass, 
	cvar_sql_db, 
	cvar_sql_table,

  Handle:sql_tuple,
  Handle:sql_connection;

public plugin_init()
{
  register_plugin(PLUGIN, VERSION, AUTHOR);

  #if defined USE_HOOK_SET_CLIENT_USER_INFO_NAME
  RegisterHookChain(RG_CBasePlayer_SetClientUserInfoName, "CBasePlayer_SetClientUserInfoName");
  #endif
  
  #if defined USE_BLOCK_MESSAGE_ON_CHANGE_NAME
  message_say_text = get_user_msgid("SayText");
  #endif
  
  #if defined USE_SQL_CFG
  cvar_sql_host	=	register_cvar("amx_sql_host", "127.0.0.1", FCVAR_PROTECTED);
  cvar_sql_db	=	register_cvar("amx_sql_db", "amxx", FCVAR_PROTECTED);
  cvar_sql_user	=	register_cvar("amx_sql_user", "root", FCVAR_PROTECTED);
  cvar_sql_pass	=	register_cvar("amx_sql_pass", "root", FCVAR_PROTECTED);
  #else
  cvar_sql_host	=	register_cvar("gate_sql_host", "127.0.0.1", FCVAR_PROTECTED);
  cvar_sql_db	=	register_cvar("gate_sql_db", "amxx", FCVAR_PROTECTED);
  cvar_sql_user	=	register_cvar("gate_sql_user", "root", FCVAR_PROTECTED);
  cvar_sql_pass	=	register_cvar("gate_sql_pass", "", FCVAR_PROTECTED);
  #endif

  #if defined USE_KICK_PLAYER
  cvar_kick_reason = register_cvar("gate_kick_reason", "Player has already been registered under this nickname");
  #endif

  cvar_sql_table = register_cvar("gate_sql_table", "gates", FCVAR_PROTECTED);
}

#if defined USE_HOOK_SET_CLIENT_USER_INFO_NAME
public CBasePlayer_SetClientUserInfoName(id, szInfoBuffer[], szNewName[])
{
  #if defined USE_BLOCK_MESSAGE_ON_CHANGE_NAME
  set_msg_block(message_say_text, BLOCK_ONCE);
  #endif

  #if defined USE_BLOCK_CHANGE_NAME_IN_GAME
  SetHookChainReturn(ATYPE_BOOL, players[id]);
  players[id] = false;
  #else
  @write_player_data(id, szNewName);
  #endif
}
#endif

public plugin_cfg()
{
  #if defined USE_FORCE_LOAD_CONFIG
    new file_path[128];
    get_localinfo("amxx_configsdir", file_path, charsmax(file_path));    
    #if defined USE_SQL_CFG
      formatex(file_path, charsmax(file_path), "%s/%s", file_path, "sql.cfg");
    #else
      formatex(file_path, charsmax(file_path), "%s/%s", file_path, "gatesql.cfg");
    #endif
    server_cmd("exec %s", file_path);
    server_exec();
  #endif

  @connect_db();
}

#if defined USE_CLIENT_PUT_IN_SERVER
public client_putinserver(id) 
{
  #if defined USE_CHANGE_NAME_ON_PUT_IN_SERVER
  @read_player_data(id);
  #endif

  #if defined USE_WRITE_NAME_ON_PUT_IN_SERVER
  if (is_player(id)) {
    new name[NAME_SIZE];
    get_user_name(id, name, charsmax(name));
    @write_player_data(id, name);
  }
  #endif
}
#endif

/**
 * Reads the player's nickname and changes it if it is different.
 */
#if defined USE_CHANGE_NAME_ON_PUT_IN_SERVER
@read_player_data(const id)
{
  if (is_player(id)) {
    static data[DATA_SIZE];
    new sql_table[SQL_DATA_SIZE], index[2];
    get_pcvar_string(cvar_sql_table, sql_table, charsmax(sql_table));

    #if defined USE_IP_FOR_IDENTITY
    new ip[IP_SIZE];
    get_user_ip(id, ip, charsmax(ip));
    format(data, charsmax(data), "SELECT `name` FROM %s WHERE ip = '%s'", sql_table, ip);
    #else
    new steamid[STEAMID_SIZE];
    format(data, charsmax(data), "SELECT `name` FROM %s WHERE steamid = '%s'", sql_table, steamid);
    #endif

    index[0] = id;
    SQL_ThreadQuery(sql_tuple, "@query_handler", .query = "SET NAMES utf8");
    SQL_ThreadQuery(sql_tuple, "@query_read_handler", data, index, charsmax(index));
  }
}
#endif

/**
 * Writes the player's nickname to the table.
 */
@write_player_data(const id, const name[])
{
  if (is_player(id)) {
    static data[DATA_SIZE];

    new steamid[STEAMID_SIZE], ip[IP_SIZE], sql_table[32];
    get_user_authid(id, steamid, charsmax(steamid));
    get_user_ip(id, ip, charsmax(ip));

    get_pcvar_string(cvar_sql_table, sql_table, charsmax(sql_table));
    format(data, charsmax(data), "REPLACE INTO %s (ip, steamid, name) VALUES ('%s', '%s', '%s')", sql_table, ip, steamid, name);

    SQL_ThreadQuery(sql_tuple, "@query_handler", .query = "SET NAMES utf8");
    SQL_ThreadQuery(sql_tuple, "@query_handler", .query = data);
  }
}

/**
 * Connects to the database.
 */
@connect_db()
{
  new sql_host[SQL_DATA_SIZE], sql_user[SQL_DATA_SIZE], sql_pass[SQL_DATA_SIZE], sql_db[SQL_DATA_SIZE];
  get_pcvar_string(cvar_sql_host, sql_host, charsmax(sql_host));
  get_pcvar_string(cvar_sql_user, sql_user, charsmax(sql_user));
  get_pcvar_string(cvar_sql_pass, sql_pass, charsmax(sql_pass));
  get_pcvar_string(cvar_sql_db, sql_db, charsmax(sql_db));

  new error, data[DATA_SIZE];
  sql_tuple = SQL_MakeDbTuple(sql_host, sql_user, sql_pass, sql_db);
  sql_connection = SQL_Connect(sql_tuple, error, data, charsmax(data));

  if(sql_connection == Empty_Handle) {
    set_fail_state("[%s] Error connecting to database (mysql)^nError: %s", PLUGIN, data);
  }

  SQL_FreeHandle(sql_connection);
  @check_table();
}

/**
 * Creates a table if it does not exist.
 */
@check_table()
{
  new sql_table[SQL_DATA_SIZE], data[DATA_SIZE];
  get_pcvar_string(cvar_sql_table, sql_table, charsmax(sql_table));

  format(data, charsmax(data), "CREATE TABLE IF NOT EXISTS `%s` \
  (`ip` varchar(%d), \
   `steamid` varchar(%d), \
   `name` varchar(%d), \
   PRIMARY KEY(`ip`))", sql_table, IP_SIZE, STEAMID_SIZE, NAME_SIZE);

  SQL_ThreadQuery(sql_tuple, "@query_handler", .query = "SET NAMES utf8");
  SQL_ThreadQuery(sql_tuple, "@query_handler", .query = data);
}

/**
 * Request handler with no execution result returned.
 */
@query_handler(fail_state, Handle: query_handle, error_message[], error_code, data[], datasize, Float: queue)
{
  if(fail_state != TQUERY_SUCCESS) {
    server_print("[%s] %s", PLUGIN, error_message);
    log_amx("[%s] %s", PLUGIN, error_message);
  }

  SQL_FreeHandle(query_handle);
}

/**
 * Handler for reading and changing the nickname.
 */
@query_read_handler(fail_state, Handle: query_handle, error_message[], error_code, data[], datasize, Float: queue)
{
  if(datasize && fail_state == TQUERY_SUCCESS) {
    new id = data[0]; // player id

    if (is_user_connected(id) && SQL_NumResults(query_handle) > 0) {
      new oldname[NAME_SIZE], curname[NAME_SIZE];
      SQL_ReadResult(query_handle, 0, oldname, charsmax(oldname));

      get_user_name(id, curname, charsmax(curname));
      if (!equal(oldname, curname)) {
        #if defined USE_BLOCK_CHANGE_NAME_IN_GAME
        players[id] = true;
        #endif

        #if defined USE_KICK_PLAYER
        new reason[256];
        get_pcvar_string(cvar_kick_reason, reason, charsmax(reason));
        server_cmd("kick #%d %s", get_user_userid(id), reason);
        #else
        set_user_info(id, "name", oldname);
        #endif
      }
    }
  } else {
    server_print("[%s] %s", PLUGIN, error_message);
    log_amx("[%s] %s", PLUGIN, error_message);
  }

  SQL_FreeHandle(query_handle);
}

/**
 * Frees the pointer to connect to the database.
 */
public plugin_end()
{
  if (sql_tuple) SQL_FreeHandle(sql_tuple);
}