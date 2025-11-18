#################################################################################
# 42_RFLINK_AB400D.pm
# Modul for FHEM to decode RFLINK_AB400D messages
#
# (c) 2025-2025 Copyright: hjgode
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
##################################
#
# values for "set global verbose"
# 4: log unknown protocols
# 5: log decoding hexlines for debugging
#
# $Id: 42_RFLINK_AB400D.pm 5598 2025-11-07 15:26:25Z hjgode $
package main;

use strict;
use warnings;

my $time_old = 0;

sub
RFLINK_AB400D_Initialize($)
{
  my ($hash) = @_;
  
  #  '20;F5;AB400DD;ID=51;SWITCH=05;CMD=OFF;'

  $hash->{Match}     = "^[0-9]{2};[0-9A-F]{2};AB400D;.*";
  $hash->{DefFn}     = "RFLINK_AB400D_Define";
  $hash->{UndefFn}   = "RFLINK_AB400D_Undef";
  $hash->{ParseFn}   = "RFLINK_AB400D_Parse";
  $hash->{AttrList}  = "IODev ignore:0,1 do_not_notify:1,0 showtime:1,0"
                      ." $readingFnAttributes";
  $hash->{Attr}      = "RFLINK_AB400D_Attr";
  
  $hash->{AutoCreate}=
        { "RFLINK_Xiron.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"} };
  # set cmds
  #$hash->{SetFn}                = \&RFLINK_AB400D_Set; # no Send Support in RFLINK for AB400D
  # get cmds
#  $hash->{GetFn}                = \&RFLINK_AB400D_Get;
  
  $hash->{PARTIAL} = "";
}

#####################################
sub
RFLINK_AB400D_Define
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

	my $a = int(@a);
	#print "a0 = $a[0]";
  return "wrong syntax: define <name> RFLINK_AB400D code" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2]; # ist sensorname

  $hash->{CODE} = $code;
	# Adresse rückwärts dem Hash zuordnen (für ParseFn)
  $modules{RFLINK_AB400D}{defptr}{$code} = $hash;  #marker 1, siehe Marker 2
  AssignIoPort($hash);
  
  return undef;
}

#####################################
sub
RFLINK_AB400D_Undef
{
  my ($hash, $name) = @_;
  delete($modules{RFLINK_AB400D}{defptr}{$name});
  return undef;
}

sub parse_RFLINK_AB400D_msg {
  Debug("parse_RFLINK_AB400D_msg...");
  my $msg = shift;
  Debug("parse_RFLINK_AB400D_msg: msg = $msg");
  
  #  '20;F5;AB400DD;ID=51;SWITCH=05;CMD=OFF;'
  #   20;06;NewKaku;ID=008440e6;SWITCH=a;CMD=OFF;
  #   20;99;AB400D;ID=49;SWITCH=01;CMD=ON;       # IT remote Terasse button 1
  #   20;07;AB400DD;ID=41;SWITCH=1;CMD=ON;
  #    0  1      2  3   4      5 6   7  8

  #my ($typ,$myName,$id,$switch,$cmd)
  my @x = split(/[;=]/, $msg);

  Debug("parse_RFLINK_AB400D_msg array scalar = ".scalar(@x));
  if ( scalar(@x) != 9 ) {
    Debug ("RFLINK_AB400D: check1 failed");
    return;    
  }
  
  my $out="";
  for (my $i=0; $i < scalar(@x); $i++){
    $out .= $i . ":" .  $x[$i] . ", ";
  }
  Debug("RFLINK: parsed to: $out");

  my $name=$x[2];
  my $id=$x[4];
  my $switch= $x[6]; #( hex($x[6]) & hex("7FFF") * 0.1 );
  my $cmd= $x[8]; #(hex($x[8]); #Xiron gives humidity in hex?

  # try to get the device with the name
  my $myName = $name . $id;

  my $chn = $x[12]; #chn for Xiron
  
  return ($name,$id,$switch,$cmd);
}

sub
RFLINK_AB400D_Parse($$)
{
  my ($iohash, $msg) = @_;

  my $time = time();
  if ($time_old ==0) {
  	Log 5, "RFLINK_AB400D: decoding delay=0 hex=$msg";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "RFLINK_AB400D: decoding delay=$time_diff hex=$msg";
  }
  $time_old = $time;
  
  my $ioname = $iohash->{NAME};

  #parse msg
    # Get values from decoder
  Debug("RFLINK: call parser_RFLINK_msg");
  my ($sensorname,$id,$switch,$cmd) = parse_RFLINK_AB400D_msg($msg);
  Debug("RFLINK: parser_RFLINK_msg=$sensorname,$id,$switch,$cmd");

  $sensorname = $sensorname . "_" . $id;

  # Get longid setting from IO_Device
  my $model= "RFLINK_AB400D";
#  Debug("RFLINK_AB400D parse, get longids setting...");
#  my $longids = AttrVal($iohash->{NAME},'longids',0);
#  if ( ($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/x)))
#  {
#    Debug("RFLINK: longids = $longids");
#    if ( length($id) > 0) {
#      $sensorname .= "_" . $id; # add chn if longids is set in iodevice
#    }
#  }else{
#    Debug("RFLINK: longids is not set or used");
#  }   

  Debug("RFLINK_AB400D_Parse: deviceCode to check = $sensorname");
  
  # Check if device is defined
#  my $def = $modules{RFLINK_AB400D}{defptr}{$sensorname}; # $modules{RFLINK_AB400D}{defptr}{$iohash->{NAME} . "." . $sensorname};
#  my $name = $def->{NAME};
#  Debug("RFLINK parse: test if defined with $name");
  #return "" if(IsIgnored($name));
  
  # wenn bereits eine Gerätedefinition existiert (via Definition Pointer aus Define-Funktion)
  # marker 2, siehe Marker 1
  my $hash = $modules{RFLINK_AB400D}{defptr}{$sensorname};
  if ($hash){
    Debug ("RFLINK: hash is: $hash");
  }else{
    Debug ("RFLINK: hash is undef");
  }
  if($hash){
    # Nachricht für $hash verarbeiten
    readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'switch', $switch); #switch is a number like 05
    readingsBulkUpdate($hash, 'cmd', $cmd);
    
    # supply one reading for this switch
    readingsBulkUpdate($hash, 'switch_' . $switch, $cmd); # should give switch_05:on|off
    
    readingsBulkUpdate($hash, 'state', 'Switch: '.$switch.' Cmd:'.$cmd);
		readingsEndUpdate($hash,1);

    Debug "RFLINK - return: ".$hash->{NAME};
		return $hash->{NAME}; # Rückgabe des Gerätenamens, für welches die Nachricht bestimmt ist.

  }else{
  	# Keine Gerätedefinition verfügbar

    # Sollte keine passende Definition gefunden werden, so muss die Parse-Funktion folgenden Rückgabewert liefern (zusammenhängende Zeichenkette):
    # UNDEFINED <Namensvorschlag> <Modulname> <Define-Parameter...>
		# Daher Vorschlag define-Befehl: <NAME> <MODULNAME> <ADDRESSE>
    
    Debug("RFLINK_AB400D - return: UNDEFINED $sensorname RFLINK_AB400D $sensorname");
    
		return "UNDEFINED $sensorname RFLINK_AB400D $sensorname";
		
    #return $io_hash->{NAME}; # kein autocreate
		#return undef;
  }
  
  return $sensorname;
}

sub RFLINK_AB400D_Attr($$$$)
{
	my ( $cmd, $name, $aName, $aValue ) = @_;
    
  	# $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $aName/$aValue sind Attribut-Name und Attribut-Wert
    
	if ($cmd eq "set") {
		if ($aName eq "Regex") {
			eval { qr/$aValue/ };
			if ($@) {
				Log3 $name, 3, "X ($name) - Invalid regex in attr $name $aName $aValue: $@";
				return "Invalid Regex $aValue: $@";
			}
		}
	}
	return undef;
}

sub RFLINK_AB400D_Set($@)
{
  Debug ("RFLINK_AB400D_Set...");
	my ( $hash, $name, $cmd, @args ) = @_;
  Debug ("RFLINK_AB400D_Set...args read: hash=$hash name=$name cmd=$cmd args=@args");

# 2025.11.17 20:04:43 1: DEBUG>RFLINK_AB400D_Set...args read: hash=HASH(0x55f89102f778) name=AB400D_49 cmd=switch_01 args=on

# $hash->{IODev} enthält IO device der Nachricht
# $hash->{READINGS} enthält alle readings

  my $readings = $hash->{READINGS};
  Debug ("############## x_set readings=");
  # my $v = $hash->{READINGS}{state}{TIME};
  #
  #    foreach my $rname (keys %{$hash->{READINGS}}) {
  #      my $rval=$hash->{READINGS}->{$rname}->{VAL};
  #      $map->{$rname}=$rval;
  #    }

  foreach my $a (keys %{$hash->{READINGS}})
  {
    Debug ("reading: $a");
  }
  
	return "\"set $name\" needs at least one argument" unless(defined($cmd));

# For switches, the protocol name has to be stored and re-used on the transmission side.
# Thus, when a remote control is used to control a device data like below will be send from the RFLink Gateway over USB:
# 20;3B;NewKaku;ID=cac142;SWITCH=3;CMD=OFF;
# When the state of this switch needs to be changed the following command has to be send:
# 10;NewKaku;0cac142;3;ON;

# example: set AB400D_51 Switch_05 on
# then cmd = switch_05  # lower case
# arg = on

# so, args should be set <name> switch <number> on|off
# check if reading switch x exists

  my $value = ReadingsVal("$name", "$cmd", 'n/a');
  Debug ("reading of name $name -> cmd $cmd args[0] $args[0] ReadingsVal $value");
  
  if ($cmd eq '?'){
    return "choose one of switch_01:on,off switch_02:on,off switch_03:on,off switch_04:on,off switch_05:on,off";
  }
  
  if ( $value eq 'n/a' or $value eq '?'){
		return "Unknown cmd $cmd, choose one of switch_01:on,off switch_02:on,off switch_03:on,off switch_04:on,off switch_05:on,off";
  }
  
  my $io = $hash->{IODev};
  return 'no IODev available, adapt attribute IODevList' if (!defined($io));

	if($cmd eq "switch_01")
	{
     # 20;3B;NewKaku;ID=cac142;SWITCH=3;CMD=OFF;
     # When the state of this switch needs to be changed the following command has to be send:
     # 10;NewKaku;0cac142;3;ON;
     my $devname = substr($name, 0, length($name)-3); # -> AB400D
     my $devid   = substr($name, -2);           # -> 49
     my $switchstr  = substr($cmd, -2);            # switch_01 -> 01
     my $switch = $switchstr + 0;
     my $devcmd  = uc $args[0];
     
     # DEBUG>RFLINK_Write...fn=Write msg=10;_49;49;1;ON;
     my $sendcmd="10;" . $devname . ";" . $devid .";" . $switch .";" . $devcmd . ";" ;
     Debug ($sendcmd);

#     readingsBeginUpdate($hash);
      my $doTrigger = 0;
     readingsSingleUpdate($hash, "sendmsg", $sendcmd, $doTrigger);
#     readingsBulkUpdate($hash, 'sendmsg', $sendcmd);
#	   readingsEndUpdate($hash,1);
     
	   if($args[0] eq "on")
	   {
	      Debug ("##### set $cmd on");

      	IOWrite($hash, 'Write', $sendcmd);
        return undef; #OK
	   }
	   elsif($args[0] eq "off")
	   {
	      Debug ("#### set $cmd off");
        return undef; # OK
	   }
	   else
	   {
        return "Unknown argument $cmd, choose one of switch_01:on,off switch_02:on,off switch_03:on,off switch_04:on,off switch_05:on,off";
	   }   
	}
	elsif($cmd eq "power")
	{
	   if($args[0] eq "on")
	   {
	      Debug ("$cmd on");
	   }
	   elsif($args[0] eq "off")
	   {
	      Debug ("$cmd on");
	   }  
	   else
	   {
	      return "Unknown value $args[0] for $cmd, choose one of on off";
	   }       
	}
	else
	{
		return "Unknown argument $cmd, choose one of switch_01:on,off switch_02:on,off switch_03:on,off switch_04:on,off switch_05:on,off";
	}
  
}

sub getSwitchReadings(@){
  my $hash = @_;
  my $str = "";
  my @list = qw (switch_01, switch_02, switch_3, switch_4, switch_5);
  foreach my $key (@list){
    my $value = $hash->{Readings}{key}{VAL};
    if ($value){
      $str .= $value . " ";
    }
  }
  return $str;
}

sub RFLINK_AB400D_Get($$@)
{
	my ( $hash, $name, $opt, @args ) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));

  my $value = ReadingsVal("$name", "$opt", 'n/a');
  Debug ("reading of name $name -> opt $opt args[0] $args[0] ReadingsVal $value");

  my $str = 'switch_01 switch_02 switch_03 switch_04 switch_05';
#  my $str = getSwitchReadings($hash);
  
  if(substr($opt,0,7) eq 'switch' and $value ne 'n/a'){
    return $value;
  }
	elsif(substr($opt,0,7) eq 'switch' and  $value eq 'n/a') 
	{
	   return "unknown option, choose on of ". $str;
	}
	else
	{
 		return "Unknown cmd $opt, choose one of switch_01 switch_02 switch_03 switch_04 switch_05";

	}
}

1;

=pod
To switch send
10;Name;id;switch;cmd

10;AB400D;49;01;OFF;

Does not work for AB400D

For switches, the protocol name has to be stored and re-used on the transmission side.
Thus, when a remote control is used to control a device data like below will be send from the RFLink Gateway over USB:
20;3B;NewKaku;ID=cac142;SWITCH=3;CMD=OFF;
When the state of this switch needs to be changed the following command has to be send:
10;NewKaku;0cac142;3;ON;
The name label (here "NewKaku") is used to tell the RFLink Gateway what protocol it has to use for the RF broadcast.
      
   
Special Control Commands - Send:   
--------------------------------   
10;REBOOT;       => Reboot RFLink Gateway hardware   
10;PING;         => a "keep alive" function. Is replied with: 20;99;PONG;   
10;VERSION;      => Version and build indicator. Is replied with: 20;99;"RFLink Gateway software version";    
10;RFDEBUG=ON;   => ON/OFF to Enable/Disable showing of RF packets. Is replied with: 20;99;RFDEBUG="state";   
10;RFUDEBUG=ON;  => ON/OFF to Enable/Disable showing of undecoded RF packets. Is replied with: 20;99;RFUDEBUG="state";  
10;QRFDEBUG=ON;  => ON/OFF to Enable/Disable showing of undecoded RF packets. Is replied with: 20;99;QRFDEBUG="state";   
                    QRFDEBUG is a faster version of RFUDEBUG but all pulse times are shown in hexadecimal and need to be multiplied by 30   
10;RTSCLEAN;     => Clean Rolling code table stored in internal EEPROM   
10;RTSRECCLEAN=9 => Clean Rolling code record number (value from 0 - 15)   
10;RTSSHOW;      => Show Rolling code table stored in internal EEPROM   
10;STATUS;       => Reports the status of the various modules that can be enabled/disabled   
                    20;B5;STATUS;setRF433=ON;NodoNRF=OFF;MilightNRF=ON;setLivingColors=ON;setAnsluta=OFF;setGPIO=OFF;   

=begin html

<a name="RFLINK_AB400D"></a>
<h3>RFLINK_AB400D</h3>
<ul>
  The RFLINK_AB400D module interprets RFXCOM RFXMeter messages received by a RFXCOM receiver. You need to define an RFXCOM receiver first.
  See the <a href="#RFXCOM">RFXCOM</a>.

  <br><br>

  <a name="RFLINK_AB400Ddefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RFLINK_AB400D &lt;deviceid&gt; [&lt;scalefactor&gt;] [&lt;unitname&gt;]</code> <br>
    <br>
    &lt;deviceid&gt; is the device identifier of the RFXMeter sensor and is a one byte hexstring (00-ff).
    <br>
    &lt;scalefactor&gt; is an optional scaling factor. It is multiplied to the value that is received from the RFXmeter sensor.
    <br>
    &lt;unitname&gt; is an optional string that describes the value units. It is added to the Reading generated to describe the values.
    <br><br>
      Example: <br>
    <code>define RFXWater RFLINK_AB400D 00 0.5 ltr</code>
      <br>
    <code>define RFXPower RFLINK_AB400D 01 0.001 kwh</code>
      <br>
    <code>define RFXGas RFLINK_AB400D 02 0.01 cu_m</code>
      <br>
  </ul>
  <br>

  <a name="RFLINK_AB400Dset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="RFLINK_AB400Dget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="RFLINK_AB400Dattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
  </ul>
</ul>

=end html
=cut
