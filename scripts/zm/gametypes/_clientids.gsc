#using scripts\codescripts\struct;

#using scripts\shared\callbacks_shared;
#using scripts\shared\system_shared;
#using scripts\shared\flag_shared;

#insert scripts\shared\shared.gsh;

#using scripts\zm\_zm_perks;

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
}

function on_player_connect()
{
	self.clientid = matchRecordNewPlayer( self );
	if ( !isdefined( self.clientid ) || self.clientid == -1 )
	{
		self.clientid = level.clientid;
		level.clientid++;	// Is this safe? What if a server runs for a long time and many people join/leave
	}

}
function on_player_spawn()
{
    level flag::wait_till("initial_blackscreen_passed");

	self func_giveWeapon("idgun_0");
	// self func_doGivePerk("specialty_rof");
	// self func_doGivePerk("specialty_armorvest");
	// self func_doGivePerk("specialty_quickrevive");
	// self func_doGivePerk("specialty_fastreload");
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