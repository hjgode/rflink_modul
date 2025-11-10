#################################################################################
# 42_RFLINK_CRESTA.pm
# Modul for FHEM to decode RFLINK_CRESTA messages
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
# $Id: 42_RFLINK_CRESTA.pm 5598 2025-11-07 15:26:25Z hjgode $
package main;

use strict;
use warnings;

my $time_old = 0;

sub
RFLINK_CRESTA_Initialize($)
{
  my ($hash) = @_;
  
  #  20;C5;Cresta;ID=4C02;TEMP=14.6;HUM=105;BAT=LOW;

  $hash->{Match}     = "^[0-9]{2};[0-9A-F]{2};Cresta;.";
  $hash->{DefFn}     = "RFLINK_CRESTA_Define";
  $hash->{UndefFn}   = "RFLINK_CRESTA_Undef";
  $hash->{ParseFn}   = "RFLINK_CRESTA_Parse";
  $hash->{AttrList}  = "IODev ignore:0,1 do_not_notify:1,0 showtime:1,0"
                      ." $readingFnAttributes";
  $hash->{Attr}      = "RFLINK_CRESTA_Attr";
  
  $hash->{AutoCreate}=
        { "RFLINK_Cresta.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"} };

  $hash->{PARTIAL} = "";
}

#####################################
sub
RFLINK_CRESTA_Define
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

	my $a = int(@a);
	#print "a0 = $a[0]";
  return "wrong syntax: define <name> RFLINK_CRESTA code" if(int(@a) != 3);

  my $name = $a[0];
  my $code = $a[2]; # ist sensorname

  $hash->{CODE} = $code;
	# Adresse rückwärts dem Hash zuordnen (für ParseFn)
  $modules{RFLINK_CRESTA}{defptr}{$code} = $hash;  #marker 1, siehe Marker 2
  AssignIoPort($hash);
  
  return undef;
}

#####################################
sub
RFLINK_CRESTA_Undef
{
  my ($hash, $name) = @_;
  delete($modules{RFLINK_CRESTA}{defptr}{$name});
  return undef;
}

sub parse_RFLINK_CRESTA_msg {
  Debug("parse_RFLINK_CRESTA_msg...");
  my $msg = shift;
  Debug("parse_RFLINK_CRESTA_msg: msg = $msg");
  # 20;C5;Cresta;ID=4C02;TEMP=14.6;HUM=105;BAT=LOW;
  #my ($typ,$myName,$id,$tmp,$hum,$bat,$chn)
  my @x = split(/[;=]/, $msg);

  Debug("parse_RFLINK_CRESTA_msg array scalar = ".scalar(@x));
  if ( scalar(@x) != 11 ) {
    Debug ("RFLINK_CRESTA: check1 failed");
    return;    
  }
  
  my $out="";
  for (my $i=0; $i < scalar(@x); $i++){
    $out .= $i . ":" .  $x[$i] . ", ";
  }
  Debug("RFLINK_CRESTA: parsed to: $out");
  # TODO: DEBUG>RFLINK: parsed to: 0:20, 1:8D, 2:Cresta, 3:ID, 4:2001, 5:TEMP, 6:9.7, 7:HUM, 8:130, 9:BAT, 10:LOW, 11:, 

  my $name=$x[2];
  my $id=$x[4];
  my $tmp= $x[6]; #( hex($x[6]) & hex("7FFF") * 0.1 );
  my $hum=sprintf("%X", $x[8]); # $x[8];
  my $bat=$x[10];
  # try to get the device with the name
  my $myName = $name . $id;

  my $chn = ""; #no chn for Cresta
  
  return ($name,$id,$tmp,$hum,$bat,$chn);
}

sub
RFLINK_CRESTA_Parse($$)
{
  my ($iohash, $msg) = @_;

  my $time = time();
  if ($time_old ==0) {
  	Log 5, "RFLINK_CRESTA: decoding delay=0 msg=$msg";
  } else {
  	my $time_diff = $time - $time_old ;
  	Log 5, "RFLINK_CRESTA: decoding delay=$time_diff msg=$msg";
  }
  $time_old = $time;
  
  my $ioname = $iohash->{NAME};

  #parse msg
    # Get values from decoder
  Debug("RFLINK_Cresta: call parse_RFLINK_CRESTA_msg");

  my ($sensorname,$id,$tmp,$hum,$bat,$chn) = parse_RFLINK_CRESTA_msg($msg);
  
  Debug("RFLINK Cresta: parse_RFLINK_CRESTA_msg=$sensorname,$id,$tmp,$hum,$bat,$chn");

  # 0x1E        Thermo/hygro-sensor
  my $sensorTyp="Thermo/hygro-sensor";

  $sensorname = $sensorname . "_" . $id;

  # Get longid setting from IO_Device
  my $model= "RFLINK_CRESTA";
  Debug("RFLINK_CRESTA parse, get longids setting...");
  my $longids = AttrVal($iohash->{NAME},'longids',0);
  if ( ($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/x)))
  {
    Debug("RFLINK_Cresta: longids = $longids");
    if ( length($chn) > 0) {
      $sensorname .= "_" . $chn; # add chn if longids is set in iodevice
    }
  }else{
    Debug("RFLINK_Cresta: longids is not set or used");
  }   

  Debug("RFLINK_CRESTA_Parse: deviceCode to check = $sensorname");
  
  # Check if device is defined
#  my $def = $modules{RFLINK_CRESTA}{defptr}{$sensorname}; # $modules{RFLINK_CRESTA}{defptr}{$iohash->{NAME} . "." . $sensorname};
#  my $name = $def->{NAME};
#  Debug("RFLINK parse: test if defined with $name");
  #return "" if(IsIgnored($name));
  
  # wenn bereits eine Gerätedefinition existiert (via Definition Pointer aus Define-Funktion)
  # marker 2, siehe Marker 1
  my $hash = $modules{RFLINK_CRESTA}{defptr}{$sensorname};
  if ($hash){
    Debug ("RFLINK_Cresta: hash is: $hash");
  }else{
    Debug ("RFLINK_Cresta: hash is undef");
  }
  if($hash){
    # Nachricht für $hash verarbeiten
    readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'temperature', $tmp);
    readingsBulkUpdate($hash, 'humidity', $hum);
    readingsBulkUpdate($hash, 'bat', $bat);
    readingsBulkUpdate($hash, 'state', 'T: '.$tmp.' H:'.$hum);
		readingsEndUpdate($hash,1);

    Debug "RFLINK_Cresta - return: ".$hash->{NAME};
		return $hash->{NAME}; # Rückgabe des Gerätenamens, für welches die Nachricht bestimmt ist.

  }else{
  	# Keine Gerätedefinition verfügbar
    # define Cresta_4102 RFLINK_Cresta Cresta_4102
    
    # Sollte keine passende Definition gefunden werden, so muss die Parse-Funktion folgenden Rückgabewert liefern (zusammenhängende Zeichenkette):
    # UNDEFINED <Namensvorschlag> <Modulname> <Define-Parameter...>
		# Daher Vorschlag define-Befehl: <NAME> <MODULNAME> <ADDRESSE>
    
    Debug("RFLINK_CRESTA - return: UNDEFINED $sensorname RFLINK_CRESTA $sensorname");
    
		return "UNDEFINED $sensorname RFLINK_CRESTA $sensorname";
		
    #return $io_hash->{NAME}; # kein autocreate
		#return undef;
  }
  
  return $sensorname;
}

sub RFLINK_CRESTA_Attr($$$$)
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

<a name="RFLINK_CRESTA"></a>
<h3>RFLINK_CRESTA</h3>
<ul>
  The RFLINK_CRESTA module interprets RFXCOM RFXMeter messages received by a RFXCOM receiver. You need to define an RFXCOM receiver first.
  See the <a href="#RFXCOM">RFXCOM</a>.

  <br><br>

  <a name="RFLINK_CRESTAdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RFLINK_CRESTA &lt;deviceid&gt; [&lt;scalefactor&gt;] [&lt;unitname&gt;]</code> <br>
    <br>
    &lt;deviceid&gt; is the device identifier of the RFXMeter sensor and is a one byte hexstring (00-ff).
    <br>
    &lt;scalefactor&gt; is an optional scaling factor. It is multiplied to the value that is received from the RFXmeter sensor.
    <br>
    &lt;unitname&gt; is an optional string that describes the value units. It is added to the Reading generated to describe the values.
    <br><br>
      Example: <br>
    <code>define RFXWater RFLINK_CRESTA 00 0.5 ltr</code>
      <br>
    <code>define RFXPower RFLINK_CRESTA 01 0.001 kwh</code>
      <br>
    <code>define RFXGas RFLINK_CRESTA 02 0.01 cu_m</code>
      <br>
  </ul>
  <br>

  <a name="RFLINK_CRESTAset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="RFLINK_CRESTAget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="RFLINK_CRESTAattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
  </ul>
</ul>

=end html
=cut
