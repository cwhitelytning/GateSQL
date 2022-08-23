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
#define VERSION "1.1.0"

/**
 * Allows you to use the connection settings from sql.cfg.
 * This is necessary first of all so as not to produce settings for the sake of connection that are already specified somewhere.
 * If not defined, custom cvars and a configuration file will be used.
 * 
 * Note that logins_sql_table must be specified 
 * for example in sql.cfg in order to use a different table name.
 */
#define USING_SQL

/**
 * If the USING_SQL define is used, then you do not need to use your own configuration.
 * However, if sql.cfg is not loaded by default, you can use it.
 * 
 * If the SQL_CFG definition is not used, uncomment to load your own configuration file.
 */
//#define USE_FORCE_LOAD_CONFIG

/**
 * Identifies the player by IP address.
 */
#define USE_IP_IDENTITY

/**
 * Identifies the player by Steam ID.
 */
//#define USE_STEAMID_IDENTITY

/**
 * Performs dual verification by address and identifier.
 * (USE_IP_IDENTITY and USE_STEAMID_IDENTITY must be defined).
 */
//#define USE_DUAL_IDENTITY

/**
 * During testing of the plugin on a real server, 
 * players with empty Steam IDs appeared in the table.
 */
//#define KICK_PLAYER_IF_STEAMID_IS_EMPTY

/**
 * Reads and changes the player's nickname.
 * If only saving the name will be commented out.
 */
#define USE_CHANGE_NAME_ON_PUT_IN_SERVER

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
#define DATA_SIZE 512
#define STEAMID_SIZE 35
#define NAME_SIZE 33
#define IP_SIZE 23

/**
 * --------------------------------------------------------------------------------------
 * Implementation
 * --------------------------------------------------------------------------------------
 */
#define is_player(%1) !is_user_bot(%1) && !is_user_hltv(%1)

#if defined USE_BLOCK_CHANGE_NAME_IN_GAME
  new unlocks[MAX_PLAYERS + 1]; //!< Forces to rename the nickname of a particular player if the name change lock is used
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
  Handle:sql_connection,
  
  indexes[MAX_PLAYERS + 1];

public plugin_natives()
{
  register_native("gate_get_player_index", "@get_player_index");
}

public plugin_end()
{
  if (sql_tuple) SQL_FreeHandle(sql_tuple);
}

public plugin_init()
{
  register_plugin(PLUGIN, VERSION, AUTHOR);

  #if defined USE_HOOK_SET_CLIENT_USER_INFO_NAME
    RegisterHookChain(RG_CBasePlayer_SetClientUserInfoName, "CBasePlayer_SetClientUserInfoName");
  #endif
  
  #if defined USE_BLOCK_MESSAGE_ON_CHANGE_NAME
    message_say_text = get_user_msgid("SayText");
  #endif
  
  #if defined USING_SQL
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

  cvar_sql_table = register_cvar("gate_sql_table", "gates", FCVAR_PROTECTED);

  #if defined USE_FORCE_LOAD_CONFIG
    new file_path[128];
    get_localinfo("amxx_configsdir", file_path, charsmax(file_path));    
    #if defined USING_SQL
      formatex(file_path, charsmax(file_path), "%s/%s", file_path, "sql.cfg");
    #else
      formatex(file_path, charsmax(file_path), "%s/%s", file_path, "gatesql.cfg");
    #endif
    server_cmd("exec %s", file_path);
  #endif
}

#if defined USE_HOOK_SET_CLIENT_USER_INFO_NAME
public CBasePlayer_SetClientUserInfoName(id, szInfoBuffer[], szNewName[])
{
  #if defined USE_BLOCK_MESSAGE_ON_CHANGE_NAME
    set_msg_block(message_say_text, BLOCK_ONCE);
  #endif

  #if defined USE_BLOCK_CHANGE_NAME_IN_GAME
    SetHookChainReturn(ATYPE_BOOL, unlocks[id]);
    unlocks[id] = false;
  #else
    @update_player_data(id, szNewName);
  #endif
}
#endif

public plugin_cfg() @connect_db();
public client_disconnected(id) { indexes[id] = 0; }
public client_putinserver(id) @read_player_data(id);

/**
 * Reads the player's nickname and changes it if it is different.
 */
@read_player_data(const id)
{
  if (is_player(id)) {
    new sql_query[DATA_SIZE], sql_table[SQL_DATA_SIZE], index[2];
    get_pcvar_string(cvar_sql_table, sql_table, charsmax(sql_table));

    #if defined USE_IP_IDENTITY
      new ip[IP_SIZE];
      get_user_ip(id, ip, charsmax(ip), true /* without port */);    
    #endif

    #if defined USE_STEAMID_IDENTITY
      new steamid[STEAMID_SIZE];
      get_user_authid(id, steamid, charsmax(steamid));
      #if defined KICK_PLAYER_IF_STEAMID_IS_EMPTY
        if (equal(steamid, "")) {
          server_cmd("kick #%d %s", get_user_userid(id), "Steam ID is empty");
          return;
        }
      #endif
    #endif

    #if defined USE_IP_IDENTITY && defined USE_STEAMID_IDENTITY && defined USE_DUAL_IDENTITY
      format(sql_query, charsmax(sql_query), "SELECT `id`, `name` FROM %s WHERE ip = '%s' AND steamid = '%s'", sql_table, steamid, ip);
    #elseif defined USE_IP_IDENTITY && defined USE_STEAMID_IDENTITY
      format(sql_query, charsmax(sql_query), "SELECT `id`, `name` FROM %s WHERE ip = '%s' OR steamid = '%s'", sql_table, steamid, ip);
    #elseif defined USE_STEAMID_IDENTITY
      format(sql_query, charsmax(sql_query), "SELECT `id`, `name` FROM %s WHERE steamid = '%s'", sql_table, steamid);
    #else
      format(sql_query, charsmax(sql_query), "SELECT `id`, `name` FROM %s WHERE ip = '%s'", sql_table, ip);
    #endif

    index[0] = id;
    SQL_ThreadQuery(sql_tuple, "@query_read_handler", sql_query, index, charsmax(index));
  }
}

/**
 * Writes the player's nickname to the table.
 */
@update_player_data(const id, name[])
{
  if (indexes[id]) {
    new steamid[STEAMID_SIZE];
    get_user_authid(id, steamid, charsmax(steamid));

    #if defined KICK_PLAYER_IF_STEAMID_IS_EMPTY
      if (equal(steamid, "")) {
        server_cmd("kick #%d %s", get_user_userid(id), "Steam ID is empty");
        return;
      }
    #endif

    new sql_query[DATA_SIZE], ip[IP_SIZE], sql_table[32];
    get_user_ip(id, ip, charsmax(ip), true /* without port */);
    mysql_escape_string(name, NAME_SIZE - 1);

    get_pcvar_string(cvar_sql_table, sql_table, charsmax(sql_table));
    format(sql_query, charsmax(sql_query), "UPDATE `%s` SET \
    `ip` = '%s', \
    `steamid` = '%s', \
    `name` = '%s', \
    `updated` = CURRENT_TIMESTAMP \
    WHERE `id` = %d", sql_table, ip, steamid, name, indexes[id]);
    SQL_ThreadQuery(sql_tuple, "@query_handler", .query = sql_query);
  }
}

/**
 * Creates a new record.
 */
@insert_player_data(const id, name[])
{
  if (is_player(id)) {
    new steamid[STEAMID_SIZE];
    get_user_authid(id, steamid, charsmax(steamid));

    #if defined KICK_PLAYER_IF_STEAMID_IS_EMPTY
      if (equal(steamid, "")) {
        server_cmd("kick #%d %s", get_user_userid(id), "Steam ID is empty");
        return;
      }
    #endif

    new ip[IP_SIZE], sql_table[32], sql_query[DATA_SIZE];
    get_user_ip(id, ip, charsmax(ip), true /* without port */);
    mysql_escape_string(name, NAME_SIZE - 1);

    get_pcvar_string(cvar_sql_table, sql_table, charsmax(sql_table));
    format(sql_query, charsmax(sql_query), "INSERT INTO %s (ip, steamid, name) VALUES ('%s', '%s', '%s')", sql_table, ip, steamid, name);

    SQL_ThreadQuery(sql_tuple, "@query_handler", .query = sql_query);
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
  SQL_SetCharset(sql_tuple, "utf8");

  sql_connection = SQL_Connect(sql_tuple, error, data, charsmax(data));

  if(sql_connection == Empty_Handle) {
    set_fail_state("[%s] Error connecting to database (mysql)^nError: %s", PLUGIN, data);
  }

  SQL_SetCharset(sql_connection, "utf8");
  SQL_FreeHandle(sql_connection);

  @check_table();
}

/**
 * Creates a table if it does not exist.
 */
@check_table()
{
  new sql_table[SQL_DATA_SIZE], sql_query[DATA_SIZE];
  get_pcvar_string(cvar_sql_table, sql_table, charsmax(sql_table));

  format(sql_query, charsmax(sql_query), "CREATE TABLE IF NOT EXISTS `%s` \
  (`id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY, \
   `ip` varchar(%d) NOT NULL, \
   `steamid` varchar(%d) NOT NULL, \
   `name` varchar(%d) NOT NULL, \
   `updated` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP) DEFAULT CHARSET=utf8", sql_table, IP_SIZE, STEAMID_SIZE, NAME_SIZE);  

  SQL_ThreadQuery(sql_tuple, "@query_handler", .query = sql_query);
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

    if (is_player(id)) {
      new curname[NAME_SIZE];
      get_user_name(id, curname, charsmax(curname));
      
      if (SQL_NumResults(query_handle)) {
        indexes[id] = SQL_ReadResult(query_handle, 0); //!< get index id

        #if defined USE_CHANGE_NAME_ON_PUT_IN_SERVER
          new oldname[NAME_SIZE];
          SQL_ReadResult(query_handle, 1, oldname, charsmax(oldname));
        
          if (!equal(oldname, curname)) {
            #if defined USE_BLOCK_CHANGE_NAME_IN_GAME
              unlocks[id] = true;
            #endif
            set_user_info(id, "name", oldname);
          }
        #else
          @update_player_data(id, curname);
        #endif
      } else {
        @insert_player_data(id, curname);
      }
    }
  } else {
    server_print("[%s] %s", PLUGIN, error_message);
    log_amx("[%s] %s", PLUGIN, error_message);
  }

  SQL_FreeHandle(query_handle);
}

/*********    mysql escape functions     ************/
mysql_escape_string(dest[],len)
{
  replace_all(dest,len,"\\","\\\\");
  replace_all(dest,len,"\0","\\0");
  replace_all(dest,len,"\n","\\n");
  replace_all(dest,len,"\r","\\r");
  replace_all(dest,len,"\x1a","\Z");
  replace_all(dest,len,"'","''");
  replace_all(dest,len,"^"","^"^"");
}

/*********            natives            ************/
/**
 * Returns player index in the table.
 * If there is no player or he does not exist in the table, returns 0.
 */
@get_player_index()
{
  new id = get_param(1);
  return indexes[id];
}