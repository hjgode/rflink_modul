# 
# 10_RFLINK.pm
#
#perl modul to interact with rflink serial
# ie 192.168.0.166 7072
# or USB

=pod
RFLink Startup communication example:

20;00;Nodo RadioFrequencyLink - RFLink Gateway V1.1 - R46;
20;01;MySensors=OFF;NO NRF24L01;
20;02;setGPIO=ON;
20;03;Cresta;ID=8301;WINDIR=0005;WINSP=0000;WINGS=0000;WINTMP=00c3;WINCHL=00c3;BAT=LOW;
20;04;Cresta;ID=3001;TEMP=00b4;HUM=50;BAT=OK;
20;05;Cresta;ID=2801;TEMP=00af;HUM=53;BAT=OK;
20;06;NewKaku;ID=008440e6;SWITCH=a;CMD=OFF;
20;07;AB400D;ID=41;SWITCH=1;CMD=ON;
20;08;SilvercrestDB;ID=04d6bb97;SWITCH=1;CMD=ON;CHIME=01;
.....
Packet structure - RFlink describing data received from RF:

Data:
20;02;Name;ID=9999;LABEL=data;

Fields:
20                         => Node number 20 means from the RFLink Gateway to the master, 10 means from the master to the RFLink Gateway
                                  Node number 11 means from the master to the master (Echo command - creation of devices), see below for explanation
;                           => field separator
02                        => packet counter (goes from 00-FF)
NAME                => Device name (can be used to display in applications etc.)
LABEL=data      => contains the field type and data for that field, can be present multiple times per device
List of Data Fields: (LABEL=data)

ID=9999 => device ID (often a rolling code and/or device channel number) (Hexadecimal)
SWITCH=A16 => House/Unit code like A1, P2, B16 or a button number etc.
CMD=ON => Command (ON/OFF/ALLON/ALLOFF) Additional for Milight: DISCO+/DISCO-/MODE0 - MODE8
SET_LEVEL=15 => Direct dimming level setting value (decimal value: 0-15)
TEMP=9999 => Temperature celcius (hexadecimal), high bit contains negative sign, needs division by 10 (0xC0 = 192 decimal = 19.2 degrees)
                      => (example negative temperature value: 0x80DC, high bit indicates negative temperature 0xDC=220 decimal the client side needs to divide by 10 to get -22.0 degrees
HUM=99       => Humidity (decimal value: 0-100 to indicate relative humidity in %)
BARO=9999       => Barometric pressure (hexadecimal)
HSTATUS=99        => 0=Normal, 1=Comfortable, 2=Dry, 3=Wet
BFORECAST=99        => 0=No Info/Unknown, 1=Sunny, 2=Partly Cloudy, 3=Cloudy, 4=Rain
UV=9999        => UV intensity (hexadecimal)
LUX=9999        => Light intensity (hexadecimal)
BAT=OK => Battery status indicator (OK/LOW)
RAIN=1234 => Total rain in mm. (hexadecimal) 0x8d = 141 decimal = 14.1 mm (needs division by 10)
RAINRATE=1234 => Rain rate in mm. (hexadecimal) 0x8d = 141 decimal = 14.1 mm (needs division by 10)
WINSP=9999 => Wind speed in km. p/h (hexadecimal) needs division by 10
AWINSP=9999 => Average Wind speed in km. p/h (hexadecimal) needs division by 10
WINGS=9999 => Wind Gust in km. p/h (hexadecimal)
WINDIR=123 => Wind direction (integer value from 0-15) reflecting 0-360 degrees in 22.5 degree steps
WINCHL => wind chill (hexadecimal, see TEMP)
WINTMP=1234 => Wind meter temperature reading (hexadecimal, see TEMP)
CHIME=123 => Chime/Doorbell melody number
SMOKEALERT=ON => ON/OFF
PIR=ON => ON/OFF
CO2=1234 => CO2 air quality
SOUND=1234 => Noise level
KWATT=9999 => KWatt (hexadecimal)
WATT=9999 => Watt (hexadecimal)
CURRENT=1234 => Current phase 1
CURRENT2=1234 => Current phase 2 (CM113)
CURRENT3=1234 => Current phase 3 (CM113)
DIST=1234 => Distance
METER=1234 => Meter values (water/electricity etc.)
VOLT=1234 => Voltage
RGBW=9999 => Milight: provides 1 byte color and 1 byte brightness value 
=cut

package main;
use strict;
use warnings;
use DevIo;

# FHEM Modulfunktionen

sub RFLINK_Initialize() {
  
  my ($hash) = @_;
  
  $hash->{DefFn}                = \&RFLINK_Define;
  $hash->{UndefFn}              = \&RFLINK_Undef;
  #$hash->{DeleteFn}             = \&RFLINK_Delete;
  $hash->{SetFn}                = \&RFLINK_Set;
  $hash->{GetFn}                = \&RFLINK_Get;
  $hash->{AttrFn}               = \&RFLINK_Attr;
  $hash->{ReadFn}               = \&RFLINK_Read;
  $hash->{ReadyFn}              = \&RFLINK_Ready;
  $hash->{NotifyFn}             = \&RFLINK_Notify;
  $hash->{RenameFn}             = \&RFLINK_Rename;
#  $hash->{ShutdownFn}           = \&RFLINK_Shutdown;
#  $hash->{DelayedShutdownFn}    = \&RFLINK_ DelayedShutdown;

  $hash->{AttrList} =
    "do_not_notify:1,0 " . 
    "header " .
    $readingFnAttributes;

  $hash->{parseParams} = 1;
  
  #$hash->{READINGS}{temperature}{VAL} für die Temperatur eines Fühlers
  #$hash->{READINGS}{temperature}{TIME} für den Zeitstempel der Messung
  #
  #ReadingsVal()

  # ($attr{$name} = $value);
}

sub setReadings() {
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, $readingName1, $wert1 );
  readingsBulkUpdate($hash, $readingName2, $wert2 );
  readingsEndUpdate($hash, 1);
}

sub RFLINK_Define($$$) {
  my ($hash, $def) = @_;
  my @a =split m{\s+}xms, $def;

  if(@a != 3) {
    my $msg = 'Define, wrong syntax: define <name> RFLINK {none | devicename[\@baudrate] | devicename\@directio | hostname:port}';
    Log3 undef, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name   = $a[0];
  my $dev = $a[2];

  if($dev eq 'none') {
    Log3 $name, 1, "$name: Define, device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
  }  elsif ($dev !~ m/\@/) { 
    if ( ($dev =~ m~^(?:/[^/ ]*)+?$~xms || $dev =~ m~^COM\d$~xms) )  # bei einer IP oder hostname wird kein \@57600 angehaengt
    {
      $dev .= '@57600' 
    } elsif ($dev !~ /@\d+$/ && ($dev !~ /^
      (?: (?:[a-z0-9-]+(?:\.[a-z]{2,6})?)*|(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])\.){3}
          (?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9]))
      : (?:6553[0-5]|655[0-2]\d|65[0-4]\d{2}|6[0-4]\d{3}|[1-5]\d{4}|[1-9]\d{0,3})$/xmsi) ) { 
      my $msg = 'Define, wrong hostname/port syntax: define <name> RFLINK {none | devicename[\@baudrate] | devicename\@directio | hostname:port}';
      Log3 undef, 2, $msg;
      return $msg;
    }
  }
  $hash->{DeviceName} = $dev;
  if($dev ne 'none') {
    $ret = DevIo_OpenDev($hash, 0, \&RFLINK_DoInit, \&RFLINK_Connect);
  } else {
  $hash->{DevState} = 'initialized';
    readingsSingleUpdate($hash, 'state', 'opened', 1);
  }

  FHEM::Core::Timer::Helper::addTimer($name, time(), \&RFLINK_IdList,"sduino_IdList:$name",0 );

  ##################### example...
  my $inter  = 300;
  if(int(@a) == 4) { 
    $inter = $a[3]; 
    if ($inter < 5) {
      return "interval too small, please use something > 5s, default is 300 seconds";
    }
  }
  #save internal
  $hash->{url} 		= $url;
  $hash->{Interval}	= $inter;
  
  #wird erst aufgerufen, wenn alle Attribute geladen wurden
  $hash->{NOTIFYDEV} = "global";
  
  #timer funktion setzen
  InternalTimer(gettimeofday()+2, "RFLINK_GetUpdate", $hash);

  #if everything OK with the define:
  return undef;
}

sub RFLINK_Connect {
  my ($hash, $err) = @_;

  # damit wird die err-msg nur einmal ausgegeben
  if (!defined($hash->{disConnFlag}) && $err) {
    mylog("Connect, ${err}");
    $hash->{disConnFlag} = 1;
  }
}

sub RFLINK_GetUpdate($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 4, "X: GetUpdate called ...";
	
	...
	
	# neuen Timer starten in einem konfigurierten Interval.
	InternalTimer(gettimeofday()+$hash->{Interval}, "X_GetUpdate", $hash);
}

sub RFLINK_CloseDevice {
  my ($hash) = @_;

  mylog("CloseDevice, closed");
  FHEM::Core::Timer::Helper::removeTimer($hash->{NAME});
  DevIo_CloseDev($hash);
  readingsSingleUpdate($hash, 'state', 'closed', 1);

  return ;
}

############################# package main
sub RFLINK_DoInit {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  my ($ver, $try) = ('', 0);
  #Dirty hack to allow initialisation of DirectIO Device for some debugging and tesing

  delete($hash->{disConnFlag}) if defined($hash->{disConnFlag});

  FHEM::Core::Timer::Helper::removeTimer($name,\&RFLINK_HandleWriteQueue,"HandleWriteQueue:$name");
  @{$hash->{QUEUE}} = ();
  $hash->{sendworking} = 0;

  if (($hash->{DEF} !~ m/\@directio/) and ($hash->{DEF} !~ m/none/) )
  {
    mylog ("DoInit, ".$hash->{DEF});
    $hash->{initretry} = 0;
    FHEM::Core::Timer::Helper::removeTimer($name,undef,$hash); # What timer should be removed here is not clear

    #RFLINK_SimpleWrite($hash, 'XQ'); # Disable receiver
    
    FHEM::Core::Timer::Helper::addTimer($name,gettimeofday() + SDUINO_INIT_WAIT_XQ, \&RFLINK_SimpleWrite_XQ, $hash, 0);
    FHEM::Core::Timer::Helper::addTimer($name,gettimeofday() + SDUINO_INIT_WAIT, \&RFLINK_StartInit, $hash, 0);
  }
  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});

  return;
}

sub RFLINK_Undef    
{                     
	my ( $hash, $name) = @_;       
  DevIo_CloseDev($hash);
  RemoveInternalTimer($hash);    
	return undef;                  
}

sub RFLINK_Delete($$)    
{                     
	my ( $hash, $name ) = @_;       

	# Löschen von Geräte-assoziiertem Temp-File
	unlink($attr{global}{modpath}."/FHEM/FhemUtils/$name.tmp";)

	return undef;
}

sub RFLINK_Get($$$)
{
	# by ($$@): my ( $hash, $name, $opt, @args ) = @_;
  my ( $hash, $a, $h ) = @_; # only if $hash->{parseParams} = 1;
  
	return "\"get $name\" needs at least one argument" unless(defined($opt));

	if($opt eq "status") 
	{
	   ...
	}
	elsif($opt eq "power")
	{
	   ...
	}
	...
	else
	{
		return "Unknown argument $opt, choose one of status power [...]";
	}
}

sub RFLINK_Set($$$)
{
  my ( $hash, $a, $h ) = @_;
#	my ( $hash, $name, $cmd, @args ) = @_;

	return "\"set $name\" needs at least one argument" unless(defined($cmd));

	if($cmd eq "status")
	{
	   if($args[0] eq "up")
	   {
	      ...
	   }
	   elsif($args[0] eq "down")
	   {
	      ...
	   }
	   else
	   {
	      return "Unknown value $args[0] for $cmd, choose one of up down";
	   }   
	}
	elsif($cmd eq "power")
	{
	   if($args[0] eq "on")
	   {
	      ...
	   }
	   elsif($args[0] eq "off")
	   {
	      ...
	   }  
	   else
	   {
	      return "Unknown value $args[0] for $cmd, choose one of on off";
	   }       
	}
	...
	else
	{
		return "Unknown argument $cmd, choose one of status power";
	}
}

sub RFLINK_Read($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	# einlesen der bereitstehenden Daten
	my $buf = DevIo_SimpleRead($hash);		
	return "" if ( !defined($buf) );
	Log3 $name, 5, "X ($name) - received data: ".$buf;    

  my $RFLINKdata = $hash->{PARTIAL};
  $hash->{logMethod}->($name, 5, "$name: Read, RAW: $RFLINKdata/$buf") if ($debug);
  $RFLINKdata .= $buf;

  while($RFLINKdata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$RFLINKdata) = split("\n", $RFLINKdata, 2);
    $rmsg =~ s/\r//;

    if ($rmsg =~ m/^\002(M(s|u|o);.*;)\003/) {
      ...
    }
  }
	# Daten an den Puffer anhängen
	$hash->{helper}{BUFFER} .= $buf;	
	Log3 $name, 5, "RFLINK ($name) - current buffer content: ".$hash->{helper}{BUFFER};

	# prüfen, ob im Buffer ein vollständiger Frame zur Verarbeitung vorhanden ist.
	if ($hash->{helper}{BUFFER} =~ "ff1002(.{4})(.*)1003(.{4})ff(.*)") {
	...

  return undef;
}

sub RFLINK_Write ($$)
{
	my ( $hash, $message, $address) = @_;
	
	DevIo_SimpleWrite($hash, $address.$message, 2);

	return undef;
}

sub RFLINK_Ready($)
{
	my ($hash) = @_;
      
	# Versuch eines Verbindungsaufbaus, sofern die Verbindung beendet ist.
	return DevIo_OpenDev($hash, 1, undef ) if ( $hash->{STATE} eq "disconnected" );

	# This is relevant for Windows/USB only
	if(defined($hash->{USBDev})) {
		my $po = $hash->{USBDev};
		my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;
		return ( $InBytes > 0 );
	}
}

sub RFLINK_Attr($$$$)
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

sub RFLINK_Notify($$)
{
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME}; # own name / hash

  return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled

  my $devName = $dev_hash->{NAME}; # Device that created the events

  my $events = deviceEvents($dev_hash,1);
  return if( !$events );

  foreach my $event (@{$events}) {
    $event = "" if(!defined($event));

    # Examples:
    # $event = "readingname: value" 
    # or
    # $event = "INITIALIZED" (for $devName equal "global")
    #
    # processing $event with further code
  }
}

sub RFLINK_Rename($$)
{
	my ( $new_name, $old_name ) = @_;

	my $old_index = "Module_X_".$old_name."_data";
	my $new_index = "Module_X_".$new_name."_data";

	my ($err, $old_pwd) = getKeyValue($old_index);
	return undef unless(defined($old_pwd));

	setKeyValue($new_index, $old_pwd);
	setKeyValue($old_index, undef);
}

sub RFLINK_Parse ($$)
{
	my ( $io_hash, $message) = @_;
	
	...
	
	return $found;
}

sub myLog($){
  my $msg = shift;
  Log 'RFLINK', 3, "RFLINK- $msg";
#  my $name = $hash->{NAME};
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;

# Beginn der Commandref

=pod
=item [helper|device|command]
=item summary Kurzbeschreibung in Englisch was MYMODULE steuert/unterstützt
=item summary_DE Kurzbeschreibung in Deutsch was MYMODULE steuert/unterstützt

=begin html
 Englische Commandref in HTML
=end html

=begin html_DE
 Deutsche Commandref in HTML
=end html

# Ende der Commandref
=cut
