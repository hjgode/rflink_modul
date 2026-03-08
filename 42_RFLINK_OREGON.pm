#################################################################################
# 42_RFLINK_OREGON.pm
# Modul for FHEM to decode RFLINK_OREGON messages
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
# $Id: 42_RFLINK_OREGON.pm 5598 2025-11-07 15:26:25Z hjgode $
package main;

use strict;
use warnings;

my $time_old = 0;

sub
RFLINK_OREGON_Initialize($)
{
  my ($hash) = @_;
  
  # 20;25;Oregon-1A2D;ID=2dbb;TEMP=00be;HUM=05;BAT=OK;
  # 00be => 193 * 0.1 °C = 19.3°C
  # 05   => 5 % ???

  $hash->{Match}     = "^[0-9]{2};[0-9A-F]{2};Oregon-1A2D;.";
  $hash->{DefFn}     = "RFLINK_OREGON_Define";
  $hash->{UndefFn}   = "RFLINK_OREGON_Undef";
  $hash->{ParseFn}   = "RFLINK_OREGON_Parse";
  $hash->{AttrList}  = "IODev ignore:0,1 do_not_notify:1,0 showtime:1,0"
                      ." $readingFnAttributes";
  $hash->{Attr}      = "RFLINK_OREGON_Attr";
  
  $hash->{AutoCreate}=
        { "RFLINK_OREGON.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"} };

  $hash->{PARTIAL} = "";
}

#####################################
sub
RFLINK_OREGON_Define
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

	my $a = int(@a);
	#print "a0 = $a[0]";
  return "wrong syntax: define <name> RFLINK_OREGON code" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2]; # ist sensorname

  $hash->{CODE} = $code;
	# Adresse rückwärts dem Hash zuordnen (für ParseFn)
  $modules{RFLINK_OREGON}{defptr}{$code} = $hash;  #marker 1, siehe Marker 2
  AssignIoPort($hash);
  
  return undef;
}

#####################################
sub
RFLINK_OREGON_Undef
{
  my ($hash, $name) = @_;
  delete($modules{RFLINK_OREGON}{defptr}{$name});
  return undef;
}

sub parse_RFLINK_OREGON_msg {
  Debug("parse_RFLINK_OREGON_msg...");
  my $msg = shift;
  Debug("parse_RFLINK_OREGON_msg: msg = $msg");
  # 20;25;Oregon-1A2D;ID=2dbb;TEMP=00be;HUM=05;BAT=OK;
  # MAYBE HEX or decimal, see TEMP= starts with 0
  
  #my ($typ,$myName,$id,$tmp,$hum,$bat,$chn)
  my @x = split(/[;=]/, $msg);

  Debug("parse_RFLINK_OREGON_msg array scalar = ".scalar(@x));
  if ( scalar(@x) != 11 ) {
    Debug ("RFLINK_OREGON: check1 failed");
    return;    
  }
  
  my $out="";
  for (my $i=0; $i < scalar(@x); $i++){
    $out .= $i . ":" .  $x[$i] . ", ";
  }
  Debug("RFLINK_OREGON: parsed to: $out");

  my $name=$x[2];

  $name =~ s/ /_/; # replace blanks inside name
  $name =~ s/-/_/; # replace dashes inside name

  # $hex_val = hex($hex_string);
  # hex doesn't require the "0x" at the beginning of the string. If it's missing it will still translate a hex string to a number.
  
  my $id=$x[4]; # randomID, changes with every battery change, use only channel info byte 2
  # substring of a fixed length
  # $sub_string2 = substr($string, 4, 5);
  
  my $tmp= ( (hex($x[6]) & hex("7FFF")) * 0.1 );
  #my $hex_temp_val = hex($tmp);
  
  my $hum=$x[8]; #sprintf("%X", $x[8]); # $x[8];
  my $bat=$x[10]; #""; #no bat for Auriol V3
  # try to get the device with the name
  my $myName = $name . $id;

  my $chn = substr($id,2,2); #chn for Auriol V3

  Debug("RFLINK_OREGON: parse_RFLINK_OREGON_msg : id=$id temp=$tmp hum=$hum bat=$bat");
  # : autocreate: define Oregon-1A2D_bb RFLINK_OREGON Oregon-1A2D_bb
  # 2026.03.08 11:16:47 1: ERROR: Invalid characters in name (not A-Za-z0-9._): Oregon-1A2D_bb
  
  return ($name,$id,$tmp,$hum,$bat,$chn);
}

sub
RFLINK_OREGON_Parse($$)
{
  my ($iohash, $msg) = @_;

  my $time = time();
  if ($time_old ==0) {
  	Log 5, "RFLINK_OREGON: decoding delay=0 msg=$msg";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "RFLINK_OREGON: decoding delay=$time_diff msg=$msg";
  }
  $time_old = $time;
  
  my $ioname = $iohash->{NAME};

  #parse msg
    # Get values from decoder
  Debug("RFLINK_OREGON: call parse_RFLINK_OREGON_msg");
  my ($sensorname,$id,$tmp,$hum,$bat,$chn) = parse_RFLINK_OREGON_msg($msg);

  Debug("RFLINK_OREGON: parse_RFLINK_OREGON_msg=$sensorname,$id,$tmp,$hum,$bat,$chn");

  # 0x1E        Thermo/hygro-sensor
  my $sensorTyp="Thermo/hygro-sensor";

  #FIXED: do not use randomID, if not longIDs
  $sensorname = $sensorname . "_" . $chn;

  # Get longid setting from IO_Device
  my $model= "RFLINK_OREGON";
  Debug("RFLINK_OREGON parse, get longids setting...");
  my $longids = AttrVal($iohash->{NAME},'longids',0);
  if ( ($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/x)))
  {
    Debug("RFLINK_OREGON: longids = $longids");
    if ( length($id) > 0) {
      $sensorname .= "_" . $id; # add id if longids is set in iodevice
    }
  }else{
    Debug("RFLINK_OREGON: longids is not set or used");
  }   

  Debug("RFLINK_OREGON_Parse: deviceCode to check = $sensorname");
  
  # Check if device is defined
#  my $def = $modules{RFLINK_OREGON}{defptr}{$sensorname}; # $modules{RFLINK_OREGON}{defptr}{$iohash->{NAME} . "." . $sensorname};
#  my $name = $def->{NAME};
#  Debug("RFLINK parse: test if defined with $name");
  #return "" if(IsIgnored($name));
  
  # wenn bereits eine Gerätedefinition existiert (via Definition Pointer aus Define-Funktion)
  # marker 2, siehe Marker 1
  my $hash = $modules{RFLINK_OREGON}{defptr}{$sensorname};
  if ($hash){
    Debug ("RFLINK_OREGON: hash is: $hash");
  }else{
    Debug ("RFLINK_OREGON: hash is undef");
  }
  if($hash){
    # Nachricht für $hash verarbeiten
    readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'temperature', $tmp);
    readingsBulkUpdate($hash, 'humidity', $hum);
    readingsBulkUpdate($hash, 'state', 'T: '.$tmp.' H:'.$hum);
		readingsEndUpdate($hash,1);

    Debug "RFLINK_OREGON - return: ".$hash->{NAME};
		return $hash->{NAME}; # Rückgabe des Gerätenamens, für welches die Nachricht bestimmt ist.

  }else{
  	# Keine Gerätedefinition verfügbar
    # define Cresta_4102 RFLINK_OREGON Cresta_4102
    
    # Sollte keine passende Definition gefunden werden, so muss die Parse-Funktion folgenden Rückgabewert liefern (zusammenhängende Zeichenkette):
    # UNDEFINED <Namensvorschlag> <Modulname> <Define-Parameter...>
		# Daher Vorschlag define-Befehl: <NAME> <MODULNAME> <ADDRESSE>
    
    Debug("RFLINK_OREGON - return: UNDEFINED $sensorname RFLINK_OREGON $sensorname");
    
		return "UNDEFINED $sensorname RFLINK_OREGON $sensorname";
		
    #return $io_hash->{NAME}; # kein autocreate
		#return undef;
  }
  
  return $sensorname;
}

sub RFLINK_OREGON_Attr($$$$)
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

1;

=pod
=begin html

<a name="RFLINK_OREGON"></a>
<h3>RFLINK_OREGON</h3>
<ul>
  The RFLINK_OREGON module interprets RFXCOM RFXMeter messages received by a RFXCOM receiver. You need to define an RFXCOM receiver first.
  See the <a href="#RFXCOM">RFXCOM</a>.

  <br><br>

  <a name="RFLINK_OREGONdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RFLINK_OREGON &lt;deviceid&gt; [&lt;scalefactor&gt;] [&lt;unitname&gt;]</code> <br>
    <br>
    &lt;deviceid&gt; is the device identifier of the RFXMeter sensor and is a one byte hexstring (00-ff).
    <br>
    &lt;scalefactor&gt; is an optional scaling factor. It is multiplied to the value that is received from the RFXmeter sensor.
    <br>
    &lt;unitname&gt; is an optional string that describes the value units. It is added to the Reading generated to describe the values.
    <br><br>
      Example: <br>
    <code>define RFXWater RFLINK_OREGON 00 0.5 ltr</code>
      <br>
    <code>define RFXPower RFLINK_OREGON 01 0.001 kwh</code>
      <br>
    <code>define RFXGas RFLINK_OREGON 02 0.01 cu_m</code>
      <br>
  </ul>
  <br>

  <a name="RFLINK_OREGONset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="RFLINK_OREGONget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="RFLINK_OREGONattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
  </ul>
</ul>

=end html
=cut
