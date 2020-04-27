#using scripts\codescripts\struct;

#using scripts\shared\callbacks_shared;
#using scripts\shared\system_shared;
#using scripts\shared\flag_shared;

#insert scripts\shared\shared.gsh;

#using scripts\zm\_zm;
#using scripts\zm\_zm_perks;
#using scripts\zm\_zm_stats;
#using scripts\zm\_zm_audio;
#using scripts\zm\_zm_powerups;
#using scripts\zm\_zm_blockers;
#using scripts\zm\_zm_utility;
#using scripts\zm\_util;
#using scripts\zm\_zm_pers_upgrades_system;

#using scripts\shared\array_shared;
#using scripts\shared\clientfield_shared;
#using scripts\shared\scoreevents_shared;

#namespace clientids;

REGISTER_SYSTEM( "clientids", &__init__, undefined )
	
function __init__()
{
	callback::on_start_gametype( &init );
	callback::on_connect( &on_player_connect );
    callback::on_spawned( &on_player_spawn);

}	

function init()
{
	// this is now handled in code ( not lan )
	// see s_nextScriptClientId 
	level.clientid = 0;

    level.round_think_func = &round_think;
}

function on_player_connect()
{
	self.clientid = matchRecordNewPlayer( self );
	if ( !isdefined( self.clientid ) || self.clientid == -1 )
	{
		self.clientid = level.clientid;
	}

}
function on_player_spawn()
{
    level flag::wait_till("initial_blackscreen_passed");

	//self func_giveWeapon("idgun_0");
	self func_doGivePerk("specialty_armorvest");

}

function round_think( restart = false )
{
/#	PrintLn( "ZM >> round_think start" );	#/
	
	level endon("end_round_think");
	
	if(!IS_TRUE(restart))
	{
		// Wait for blackscreen to end if in use
		if ( IsDefined( level.initial_round_wait_func ))
			[[level.initial_round_wait_func]]();
		
		if(!IS_TRUE(level.host_ended_game))
		{
			//unfreeze the players controls now
			players = GetPlayers();
			foreach(player in players)
			{
				if(!IS_TRUE(player.hostMigrationControlsFrozen))
				{
					player FreezeControls(false);
					/# println(" Unfreeze controls 8"); #/
				}

				// set the initial round_number
				player zm_stats::set_global_stat( "rounds", level.round_number );
			}
		}
	}

    // testing
    level.round_number = 258;
	level.zombie_vars["zombie_spawn_delay"] = 0.1; // max spawn rate

    SetRoundsPlayed( level.round_number );


	for( ;; )
	{
		//////////////////////////////////////////
		//designed by prod DT#36173
		maxreward = 50 * level.round_number;
		if ( maxreward > 500 )
			maxreward = 500;
		level.zombie_vars["rebuild_barrier_cap_per_round"] = maxreward;
		//////////////////////////////////////////

		level.pro_tips_start_time = GetTime();
		level.zombie_last_run_time = GetTime();	// Resets the last time a zombie ran
	
		if ( IsDefined( level.zombie_round_change_custom ) )
		{
			[[ level.zombie_round_change_custom ]]();
		}
		else 
		{
			if( !IS_TRUE( level.sndMusicSpecialRound ) )
			{
				if( IS_TRUE(level.sndGotoRoundOccurred))
					level.sndGotoRoundOccurred = false;
				else if( level.round_number == 1 )
					level thread zm_audio::sndMusicSystem_PlayState( "round_start_first" );
				else if( level.round_number <= 5 )
					level thread zm_audio::sndMusicSystem_PlayState( "round_start" );
				else
					level thread zm_audio::sndMusicSystem_PlayState( "round_start_short" );
			}
			zm::round_one_up();
			//		round_text( &"ZOMBIE_ROUND_BEGIN" );
		}

		zm_powerups::powerup_round_start();

		players = GetPlayers();
		array::thread_all( players, &zm_blockers::rebuild_barrier_reward_reset );
		
		if(!IS_TRUE(level.headshots_only) && !restart ) //no grenades for headshot only mode, or when grief restarts the round after everyone dies
		{
			level thread zm::award_grenades_for_survivors();
		}
		
	/#	PrintLn( "ZM >> round_think, round="+level.round_number+", player_count=" + players.size );		#/

		level.round_start_time = GetTime();
	
		//Not great fix for this being zero - which it should NEVER be! (post ship - PETER)
		while( level.zm_loc_types[ "zombie_location" ].size <= 0 )
		{
			wait( 0.1 );
		}

	/#
		//Reset spawn counter for zones
		zkeys = GetArrayKeys( level.zones );
		for ( i = 0; i < zkeys.size; i++ )
		{
			zoneName = zkeys[i];
			level.zones[zoneName].round_spawn_count = 0;
		}
	#/

		level thread [[level.round_spawn_func]]();

		level notify( "start_of_round" );
		//RecordZombieRoundStart();

		players = GetPlayers();
		for ( index = 0; index < players.size; index++ )
		{
			//players[index] recordRoundStartStats();
		}
		if(isDefined(level.round_start_custom_func))
		{
			[[level.round_start_custom_func]]();
		}
		
		[[level.round_wait_func]]();

		level.first_round = false;
		level notify( "end_of_round" );

		//UploadStats();
		
		if(isDefined(level.round_end_custom_logic))
		{
			[[level.round_end_custom_logic]]();
		}
		
		players = GetPlayers();
		
		// PORTIZ 7/27/16: now that no_end_game_check is being used more regularly, I was tempted to remove/change this because it seems to arbitrarily add 
		// the revival of last stand players on top of whatever mechanic toggled the bool in the first place. however, it doesn't seem to do harm, and I'd rather avoid
		// affecting these core systems if possible. for example, is there badness if a round transitions/starts and ALL players are in last stand? this can be revisited if
		// any specific bugs/exploits arise from it...
		if( IS_TRUE(level.no_end_game_check) )
		{
			level thread zm::last_stand_revive();
			level thread zm::spectators_respawn();
		}
		else if ( 1 != players.size )
		{
			level thread zm::spectators_respawn();
			//level thread last_stand_revive();
		}

		players = GetPlayers(); 
		array::thread_all( players, &zm_pers_upgrades_system::round_end );

		if ( int(level.round_number / 5) * 5 == level.round_number )
		{
			level clientfield::set( "round_complete_time", int( ( level.time - level.n_gameplay_start_time + 500 ) / 1000 ) );
			level clientfield::set( "round_complete_num", level.round_number );
		}
		
		// 
		// Increase the zombie move speed
		//level.zombie_move_speed = level.round_number * level.zombie_vars["zombie_move_speed_multiplier"];

		if( level.gamedifficulty == 0 ) //easy
		{
			level.zombie_move_speed			= level.round_number * level.zombie_vars["zombie_move_speed_multiplier_easy"]; 
		}
		else	//normal
		{
			level.zombie_move_speed			= level.round_number * level.zombie_vars["zombie_move_speed_multiplier"]; 
		}

		set_round_number( 1 + get_round_number() );
		//SetRoundsPlayed( get_round_number() );

		// Here's the difficulty increase over time area
		//level.zombie_vars["zombie_spawn_delay"] = get_zombie_spawn_delay( level.round_number );
		level.zombie_vars["zombie_spawn_delay"] = [[level.func_get_zombie_spawn_delay]]( get_round_number() );

		//	round_text( &"ZOMBIE_ROUND_END" );
		
		matchUTCTime = GetUTC();

		players = GetPlayers(); // delay in round_over allows a player that leaves during that time to remain in the players array - leading to round based SRES.  Bad.
		foreach(player in players)
		{
			if ( level.curr_gametype_affects_rank && get_round_number() > (3 + level.start_round) )
			{
				player zm_stats::add_client_stat( "weighted_rounds_played",get_round_number() );
			}
			player zm_stats::set_global_stat( "rounds", get_round_number() );

			// update the game played time
			player zm_stats::update_playing_utc_time( matchUTCTime );
			
			// Reset the health if necessary
			player zm_perks::perk_set_max_health_if_jugg( "health_reboot", true, true );

			//XP event stuff
			for ( i = 0; i < 4; i++ )
			{
				player.number_revives_per_round[i] = 0;
			}

			if ( IsAlive( player ) && player.sessionstate != "spectator" && !IS_TRUE( level.skip_alive_at_round_end_xp ) )
			{
				player zm_stats::increment_challenge_stat( "SURVIVALIST_SURVIVE_ROUNDS" );

				score_number = get_round_number() - 1;
				if ( score_number < 1 )
				{
					score_number = 1;
				}
				else if ( score_number > 20 )
				{
					score_number = 20;
				}
				scoreevents::processScoreEvent( ("alive_at_round_end_" + score_number), player );
			}
		}
		
		if( isdefined( level.check_quickrevive_hotjoin ) )
		{
			[[ level.check_quickrevive_hotjoin ]]();
		}
		
		level.round_number = get_round_number();  

		level zm::round_over();

		level notify( "between_round_over" );

		level.skip_alive_at_round_end_xp = false;
		
		restart = false;
	}
}

function set_round_number( new_round ) 
{
	// if ( new_round > 255 )
	// 	new_round = 255; 
	level.round_number = new_round; 
}

function get_round_number() 
{
	return level.round_number; 
}

function func_giveWeapon(weapon)
{
    self TakeWeapon(self GetCurrentWeapon());
    weapon = getWeapon(weapon);
    self GiveWeapon(weapon);
    self GiveMaxAmmo(weapon);
    self SwitchToWeapon(weapon);
    self iprintln(weapon+" ^2Given");
}

function func_doGivePerk(perk)
{
    if (!(self hasperk(perk) || self zm_perks::has_perk_paused(perk)))
    {
        self zm_perks::vending_trigger_post_think( self, perk );
    }
    else
    {
        self notify(perk + "_stop");
        self iprintln("Perk [" + perk + "] ^1Removed");
    }
}