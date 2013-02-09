#!/usr/bin/env perl

#############################################################################
#snmp_rename_port.pl	
#Used to change access vlan on a cisco switch port

use strict;
use warnings; 
use Net::SNMP;
use Getopt::Long;
use Term::ANSIColor;
use vars qw($opt_d $opt_h $opt_n $opt_p $opt_H $opt_w $PROGNAME);
########################################################################################
#NOTES:
#Exit codes are 0 ok, 1 user error, 2 script error. Very little output is given if you don't 
# specify debugging or an error occurs. This may need to change, who knows
#
#Also, I used red text for any error that requires the user's attention
#
########################################################################################
#Define variables
my $PROGNAME = "cisco_change_vlan.pl";

#Define oids we are going to use:
my %oids = (
	'ifDescr'							=> ".1.3.6.1.2.1.2.2.1.2",
	'vlanTrunkPortEncapsulationType'	=> ".1.3.6.1.4.1.9.9.46.1.6.1.1.3",
	'vlanPortVlan'						=> ".1.3.6.1.4.1.9.5.1.9.3.1.3",
	'portIfIndex'						=> ".1.3.6.1.4.1.9.5.1.4.1.1.11",
	'ifalias'							=> ".1.3.6.1.2.1.31.1.1.1.18",
	'vtpVlanState'						=> ".1.3.6.1.4.1.9.9.46.1.3.1.1.2",
);

my %dynamic_oids = ();

my $null_var; #Anything we don't care about but need a variable for some sort of task, use this
my $opt_help;
my $opt_d;
my $opt_vlan;
my $opt_port;
my $opt_host;
my $opt_wcom;
my $opt_name;
my $port_number;
my $value_inter;
my $human_error;
my $exit_request;
my $human_status;
my $vlan_exits = 0;
my $sp_number;


########################################################################################
Getopt::Long::Configure('bundling');
GetOptions
	("h"   => \$opt_help, "help" => \$opt_help,
	 "d"   => \$opt_d, "debug" => \$opt_d,
	 "v=s" => \$opt_vlan, "vlan=s" => \$opt_vlan,
	 "p=s" => \$opt_port, "port=s" => \$opt_port,
	 "H=s" => \$opt_host, "hostname=s" => \$opt_host,
	 "w=s" => \$opt_wcom, "wcommunity=s" => \$opt_wcom,
	 "n=s" => \$opt_name, "name=s" => \$opt_name);
	

#validate input

if ($opt_help) {

print "

This script can be used to change the access vlan of a switch port. I will not change trunk ports. 

Usage: $PROGNAME -H <host> -v vlanID -p port -w community -n name [-d] 

-h, --help
   Print this message
-H, --hostname=HOST
   Name or IP address of the switch/router to change the vlan on
-v, --vlan = Vlan ID
   Vlan ID to set the given port's access vlan to
-p, --port = port
   Port to change (ex: FastEthernet1/0/2)
-w, --wcommunity=community
   SNMPv1 write community
-n, --name=name
   Device/server name (ex mail04)
   
-d, --debug
   Enable debugging (Are you a human? Yes? Great! you will more then likely want to use this flag to see what is going on. Or not if you are utterly boring....)
   
";
exit (0);
}

unless ($opt_host) {print colored ['red'],"Host name/address not specified\n"; print color("reset"); exit (1)};
my $host = $1 if ($opt_host =~ /([-.A-Za-z0-9]+)/);
unless ($host) {print colored ['red'],"Invalid host: $opt_host\n"; print color("reset"); exit (1)};

unless ($opt_vlan) {print colored ['red'], "Vlan ID not specified\n"; print color("reset"); exit (1)};
my $vlanid = $opt_vlan;

unless ($opt_port) {print colored ['red'],"Port not specified\n"; print color("reset"); exit (1)};
my $requested_port = $opt_port;

unless ($opt_wcom) {print colored ['red'],"Write community not specified\n"; print color("reset"); exit (1)};
my $snmp_community = $opt_wcom;

unless ($opt_name) {print colored ['red'],"Device name not specified\n"; print color("reset"); exit (1)};
my $device_name = $opt_name;

########################################################################################
#start new snmp session
my($snmp,$snmp_error) = Net::SNMP->session(-hostname => $host,
                                           -community => $snmp_community);
        
print "$host, $snmp_community";
                                   
debugOutput("\n**DEBUGGING IS ENABLED**\n");
debugOutput("**DEBUG: Attempting to find the requested port: \"$requested_port\" and change the vlan to: \"$vlanid\" on $host, please stand by.....");


#walk the interface descriptions
debugOutput("**DEBUG: Walking IF-MIB::ifDescr so we have a list of interfaces \(this may take some time...\)");
my $snmp_walk_out = $snmp->get_entries( -columns =>  [$oids{ifDescr}]);
checkSNMPStatus("Couldn't poll device: ",2);

debugOutput("**DEBUG: Walking IF-MIB::ifDescr succeeded, looking to see if $requested_port exists ");

#See if the requested interface exists
LOOK_FOR_INTERFACE: while ( ($port_number,$value_inter) = each %$snmp_walk_out ) {

	#see if the current value from the hash matches
    if ($value_inter eq $requested_port) {
    	
    	debugOutput("**DEBUG: Found $requested_port in the IF-MIB::ifDescr walk ");
    	    	
    	#lets get the port number, basically take the index and remove the oid. Also, chomping seems required for some other snmp things to work right
    	$port_number =~ s/$oids{ifDescr}\.//;
    	chomp($port_number);
    	
    	last LOOK_FOR_INTERFACE;
    
    }    
    
}

unless ($port_number) {print colored ['red'], "ERROR: Interface $requested_port not found, check your spelling, syntax or reality and try again. \n"; print color("reset"); exit 2;}

debugOutput("**DEBUG: Object id for $requested_port : $port_number");

#walk CISCO-STACK-MIB::portIfIndex
debugOutput("**DEBUG: Walking CISCO-STACK-MIB::portIfIndex so we have a list of stack interfaces \(this may take some time...\)");
my $snmp_walk_out2 = $snmp->get_entries( -columns =>  [$oids{portIfIndex}]);
checkSNMPStatus("Couldn't poll device: ",2);

debugOutput("**DEBUG: Walking CISCO-STACK-MIB::portIfIndex succeeded, looking to see if $port_number exists ");

#See if the requested interface exists
LOOK_FOR_STACK_INTERFACE: while ( ($sp_number,$value_inter) = each %$snmp_walk_out2 ) {

	#see if the current value from the hash matches
    if ($value_inter eq $port_number) {
    	
    	debugOutput("**DEBUG: Found $port_number in the CISCO-STACK-MIB::portIfIndex walk ");
    	    	
    	#lets get the port number, basically take the index and remove the oid. Also, chomping seems required for some other snmp things to work right
    	$sp_number =~ s/$oids{portIfIndex}\.//;
    	chomp($sp_number);

    	last LOOK_FOR_STACK_INTERFACE;
    
    }    
    
}

unless ($port_number) {print colored ['red'], "ERROR: Interface $requested_port not found, check your spelling, syntax or reality and try again. \n"; print color("reset"); exit 2;}

debugOutput("**DEBUG: Object id for $port_number : $sp_number");

#define new hash for dynamic oids
%dynamic_oids = (
	'vlanTrunkPortEncapsulationType_port'		=> "$oids{vlanTrunkPortEncapsulationType}.$port_number",
	'ifDescr_port'								=> "$oids{ifDescr}.$port_number",
	'vlanPortVlan_port'							=> "$oids{vlanPortVlan}.$port_number",
	'ifalias_port'								=> "$oids{ifalias}.$port_number",
);

#get port description
my $port_alias_h = $snmp->get_request( -varbindlist => [$dynamic_oids{ifalias_port}]);
checkSNMPStatus("ERROR: could get the port description",2);
($null_var,my $port_alias) = each %$port_alias_h;

#check to see if the port alias matches the hostname 
debugOutput("**DEBUG: Checking if switch/router port name matches requested hostname");
if ($port_alias =~ /$device_name/i) {
	debugOutput("**DEBUG: Switch/router port name does matches requested hostname");

}
#hostname does not match. the previous action was to exit, now we ask the user if they want to change it.
else {
	if ($opt_d) {
		print colored ['red'],"The switch port description of the port listed in rack monkey does not match the hostname you provided \(found description: $port_alias\). \n\n"; print color("reset"); print "Do you want to update the port description \(be sure the data in rack monkey is correct!\)? [y/n] ";
	
		my $change_ans = <>;
		$change_ans = lc ($change_ans);
		chomp ($change_ans);
	
		if ($change_ans eq "yes" || $change_ans eq "y") {
			debugOutput("**DEBUG: Running program to change switch port");
			system ("/usr/local/adm/snmp_rename_port.pl -H $host -p $requested_port -n \"$device_name\" -w $snmp_community -d");
			if ($? != 0) { 
				print colored ['red'],"Failed to change port description.... Exiting...";print color("reset"); debugOutput("\n"); exit 2;

			}
		debugOutput("**DEBUG: Changed port description successfully");

		}
	
		else {
			print colored ['red'],"User entered no \(or rather a lack of yes\).... Exiting...."; print color("reset"); debugOutput("\n");
			exit 1;

		}
	}

	else {
	print colored ['red'],"The switch port description of the port listed in rack monkey does not match the hostname you provided \(found description: $port_alias\). You must update the switchport or run this script in debug mode. "; print color("reset"); debugOutput("\n");exit 2;

	}

}

#Check to see if port is a trunk port, if it is, we are going to scream, cry, and serpentine
debugOutput("**DEBUG: checking if $requested_port is an access or trunk port");

#get the ports encap.
my $port_encap_h = $snmp->get_request( -varbindlist => [$dynamic_oids{vlanTrunkPortEncapsulationType_port}]);
checkSNMPStatus("ERROR: could not get check encapsulation type. In some odd cases this could mean the requested port is a trunk port and I will not change a trunk port. Please check the provided port, change to an access port if it is set to a trunk port, and try again: ",2);

#check if the port is a trunk or not
($null_var,my $port_encap) = each %$port_encap_h;

#Oh hell, it's a trunk port. Serpentine Shelly. Serpentine!
if ($port_encap eq 4) {print colored ['red'],"ERROR: Requested port is a trunk port and I will not modify a trunk port! Please check the provided port, change to an access port, and try again"; print color("reset"); debugOutput("\n");exit (2)};

debugOutput("**DEBUG: Requested port not found to be a trunk port");

#get vlans, check if requested vlan already exists
debugOutput("**DEBUG: Looking for vlans");

#my $info = $snmp->get_entries(-columns => [$oids{ifDescr}], -startindex => "1", -endindex => "4096" ); #this is so we only look for the first 4096 interfaces. vlans are 1-4096
my $info = $snmp->get_entries(-columns => [$oids{vtpVlanState}]); #looks like the vlan will not show up in ifdescr under some circumstances. trying vtpvlanstate....
checkSNMPStatus("ERROR: Could not get list of vlans:",2);

my $numofvlans = scalar keys %$info;
debugOutput("**DEBUG: Found $numofvlans vlans");


LOOK_FOR_VLAN: foreach my $oid (grep /^$oids{vtpVlanState}\./, keys(%$info)) {
		
	my($index) = $oid =~ m|\.(\d+)$|;
	my $current_vlan = join(',', $index);
	
	if ($current_vlan eq $vlanid){
		debugOutput("**DEBUG: vlan $vlanid exists on $host");
		$vlan_exits = 1;
		last LOOK_FOR_VLAN; #break the loop
	}
	
}

#check to see if vlan was found
unless ($vlan_exits) {print colored ['red'],"The vlan you requested is not currently in use on the switch. Please check the provided vlan, add it to the switch, and try again"; print color("reset"); debugOutput("\n"); exit (2)};

#re-assign value
$dynamic_oids{vlanPortVlan_port} = "$oids{vlanPortVlan}.$sp_number";

#get the old vlan
my $old_vlan_h = $snmp->get_request( -varbindlist => [$dynamic_oids{vlanPortVlan_port}]);
checkSNMPStatus("ERROR: could not get old vlan",2);
($null_var,my $old_vlan) = each %$old_vlan_h;
debugOutput("**DEBUG: Current vlan is $old_vlan");

#set the new port vlan, exit if fails
debugOutput("**DEBUG: setting new vlan for $requested_port");
my $snmp_set_status = $snmp->set_request( -varbindlist => [$dynamic_oids{vlanPortVlan_port}, INTEGER, $vlanid]);
checkSNMPStatus("ERROR: could not set new vlan",2);


#confirm new vlan
my $new_vlan_h = $snmp->get_request( -varbindlist => [$dynamic_oids{vlanPortVlan_port}]);
checkSNMPStatus("ERROR: could confirm new vlan",2);
($null_var,my $new_vlan) = each %$new_vlan_h;


##If user requested debugging, give summary
debugOutput("\n**DEBUG: Old vlan of $requested_port: $old_vlan");
debugOutput("**DEBUG: New vlan of $requested_port: $new_vlan\n\n");
debugOutput("**DEBUG: DONE. Please wait while the ethernet port restarts.\n");

#Otherwise, if no debug was requested, say done and exit with status of 0
unless ($opt_d) {print "Done. Old vlan: $old_vlan | New vlan: $new_vlan ";}

########################################################################################
#Functions!

#This function will do the error checking and reporting when related to SNMP
sub checkSNMPStatus {
	$human_error = $_[0];
	$exit_request = $_[1];
	$snmp_error = $snmp->error();
    
    #check if there was an error, if so, print the requested message and the snmp error. I used the color red to get the user's attention.
    if ($snmp_error) {
		print colored ['red'], "$human_error $snmp_error \n";
		print color("reset");
		#check to see if the error should cause the script to exit, if so, exit with the requested code
		if ($exit_request) {
			exit $exit_request;
		}
	}
}

#This function will be used to give the user output, if they so desire
sub debugOutput {
	$human_status = $_[0];
    if ($opt_d) {
		print "$human_status \n";
		
	}
}


#Well shucks, we made it all the way down here with no errors. Guess we should exit without an error ;)
print color("reset");
exit 0;

