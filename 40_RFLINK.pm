#################################################################################
# 40_RFLINK.pm
# Modul for FHEM

# define myRFLINK RFLINK 192.168.0.166:7072

# Tested with USB-RFLINK-Receiver (433.92MHz, USB, order code 80002)
# (see http://www.rflinkcom.com/).
# To use this module, you need to define an RFLINK receiver:
#	define RFLINK RFLINK /dev/ttyUSB0
#
# The module also has code to access LAN based RFLINK receivers like 81003 and 83003.
#
# To use it define the IP-Adresss and the Port:
#	define RFLINK RFLINK 192.168.169.111:10001
# optionally you may issue not to initialize the device (useful for FHEM2FHEM raw 
# and if you share an RFLINK device with other programs) 
#	define RFLINK RFLINK 192.168.169.111:10001 noinit
#
# The RFLINK receivers supports lots of protocols that may be implemented for FHEM 
# writing the appropriate FHEM modules.
# Special thanks to RFLINK, http://www.rflinkcom.com/, for their help. 
# I own an USB-RFLINK-Receiver (433.92MHz, USB, order code 80002) and highly recommend it.
# 
###########################
#
# (c) 2010-2014 Copyright: Willi Herzig (Willi.Herzig@gmail.com)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# The GNU General Public License may also be found at http://www.gnu.org/licenses/gpl-2.0.html .
###########################
# $Id: 40_RFLINK.pm 11307 2016-04-25 08:02:06Z rudolfkoenig $

package main;

require "42_RFLINK_AURIOL_V3.pm";
require "42_RFLINK_CRESTA.pm";
require "42_RFLINK_XIRON.pm";

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

my $last_rmsg = "abcd";
my $last_time = 1;

sub RFLINK_Clear($);
sub RFLINK_Read($);
sub RFLINK_Ready($);
sub RFLINK_SimpleWrite(@);
sub RFLINK_SimpleRead($);
sub RFLINK_Ready($);
sub RFLINK_Parse($$$$);

sub RFLINK_OpenDev($$);
sub RFLINK_CloseDev($);
sub RFLINK_Disconnected($);

sub
RFLINK_Initialize
{
  my ($hash) = @_;

  Debug("RFLINK_Initialize...");
  
  require "$attr{global}{modpath}/FHEM/DevIo.pm";


  #possible Client modules
  $hash->{Clients} =
        ":RFLINK_CRESTA:RFLINK_XIRON:RFLINK_AURIOL_V3:";

  #Dispatch list
  # accepted inputs
=pod
  20;C5;Cresta;ID=4C02;TEMP=14.6;HUM=105;BAT=LOW;
  20;C6;Cresta;ID=2001;TEMP=9.7;HUM=104;BAT=LOW;
  20;C7;Xiron;ID=6802;TEMP=16.1;HUM=57;BAT=OK;CHN=0002;
  20;C8;AB400D;ID=51;SWITCH=05;CMD=OFF;
  20;C9;Cresta;ID=8401;TEMP=21.0;HUM=89;BAT=LOW;
  20;CA;Cresta;ID=2001;TEMP=9.7;HUM=104;BAT=LOW;
  20;CB;Auriol V3;ID=8202;TEMP=8.0;HUM=97;
  20;E2;Auriol V3;ID=8202;TEMP=7.1;HUM=105;
=cut
  # Dispatch to
  # 42_RFLINK_CRESTA
  # 42 RFLINK_XIRON
  # 42_RFLINK_AURIOL_V3
  # rest ignored
  
  my %mc = (
    "1:RFLINK_CRESTA"      => "^[0-9]{2};[0-9A-F]{2};Cresta;.*",
    "2:RFLINK_XIRON"       => "^[0-9]{2};[0-9A-F]{2};Xiron;.*", #38-78
    "3:RFLINK_AURIOL_V3"   => "^[0-9]{2};[0-9A-F]{2};Auriol_V3;.*" #"3:RFLINK_AURIOL_V3"   => "^[0-9]{2};[0-9A-F]{2};Auriol V3;.*",
  );
  $hash->{MatchList} = \%mc;

  # Provider
  $hash->{ReadFn}  = "RFLINK_Read";
  $hash->{ReadyFn} = "RFLINK_Ready";
  $hash->{WriteFn} = "RFLINK_Write";
  # Normal devices
  $hash->{DefFn}   = "RFLINK_Define";
  $hash->{UndefFn} = "RFLINK_Undef";
  $hash->{GetFn}   = "RFLINK_Get";
  $hash->{StateFn} = "RFLINK_SetState";
  $hash->{AttrList}= "dummy:1,0 do_not_init:1:0 longids loglevel:0,1,2,3,4,5,6";
  $hash->{ShutdownFn} = "RFLINK_Shutdown";
  $hash->{NotifyFn}   = "RFLINK_Notify";
  $hash->{AttrFn}   = "RFLINK_Attr";
  
  Debug("RFLINK_Initialize...finished");

}

#####################################
sub
RFLINK_Define($$)
{
  my ($hash, $def) = @_;
 
  Debug("RFLINK_Define...");
 
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> RFLINK devicename [noinit]"
    if(@a != 3 && @a != 4);

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  my $opt = $a[3] if(@a == 4);;

  if($dev eq "none") {
    Log 1, "RFLINK: $name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }

  if($dev !~ /\@/) {
	Log 1,"RFLINK: added baudrate 4800 as default";
	$dev .= "\@4800";
  }

  if(defined($opt)) {
    if($opt eq "noinit") {
      Log 1, "RFLINK: $name no init is done";
      $attr{$name}{do_not_init} = 1;
    } else {
      return "wrong syntax: define <name> RFLINK devicename [noinit]"
    }
  }
  
  
  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "RFLINK_DoInit");

  Debug("RFLINK_Define...finished");

  return $ret;
}

sub RFLINK_Get
{
  my ($hash,$name, @a) = @_;

  return "\"get RFLINK\" needs at least one parameter" if(@a < 1);

  return "Unknown argument $a[0], choose one of supported commands";

#  return $rcode;    # We will exit here, and give an output only, $rcode has some value

}

#####################################
sub
RFLINK_Write($$$)
{
  my ($hash,$fn,$msg) = @_;
      Debug("RFLINK_Write...");

  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);

  return if(!defined($fn));

  my $bstring;
  $bstring = "$fn$msg";
  Log 5, "$hash->{NAME} sending $bstring";

  DevIo_SimpleWrite($hash, $bstring, 1);
}

#####################################
sub
RFLINK_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
    Debug("RFLINK_Undef...");

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log GetLogLevel($name,$lev), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
RFLINK_Shutdown($)
{
  my ($hash) = @_;
      Debug("RFLINK_Shutdown...");

  return undef;
}

#####################################
sub
RFLINK_SetState($$$$)
{
      Debug("RFLINK_SetState...");

  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

sub
RFLINK_Clear($)
{
  my $hash = shift;
    Debug("RFLINK_Clear...");

  my $buf;

  # clear buffer:
  if($hash->{USBDev}) {
    while ($hash->{USBDev}->lookfor()) { 
    	$buf = DevIo_SimpleRead($hash);
    }
  }
  if($hash->{TCPDev}) {
   # TODO
    Debug("RFLINK_Clear return buf...");
    return $buf;
  }
      Debug("RFLINK_Clear...finished");

}

sub RFLINK_Notify ($$) {
    my ( $own_hash, $dev_hash ) = @_;

  Debug("RFLINK_Notify...");

    my $ownName = $own_hash->{NAME};    # own name / hash

    return "" if ( IsDisabled($ownName) );    # Return without any further action if the module is disabled

    my $devName = $dev_hash->{NAME};          # Device that created the events

    return "" if ( $devName ne $ownName );    # we just want to treat Devio events for own device

    my $events = deviceEvents( $dev_hash, 1 );
    return if ( !$events );

    foreach my $event ( @{$events} ) {

        #Log3 $ownName, 1, "RFLINK received $event";
        if ( $event eq "DISCONNECTED" ) {
            readingsSingleUpdate( $own_hash, "state", "disconnected", 1 );
        }
    }
    Debug("RFLINK_Notify...finished");

}

#####################################
sub
RFLINK_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;
  my $buf;
  my $char = undef ;

  Debug("RFLINK_DoInit...");

  if(defined($attr{$name}) && defined($attr{$name}{"do_not_init"})) {
    	Log 1, "RFLINK: defined with noinit. Do not send init string to device.";
  	$hash->{STATE} = "Initialized";

        # Reset the counter
        delete($hash->{XMIT_TIME});
        delete($hash->{NR_CMD_LAST_H});

    return undef;
  }

  RFLINK_Clear($hash);

  #
  # Init
  my $init = '\n';
  DevIo_SimpleWrite($hash, $init, 0);
  sleep(1);

  $buf = DevIo_TimeoutRead($hash, 0.1);
  if (defined($buf)) { $char = ord($buf); }
  if (! $buf) {
    Log 1, "RFLINK: Initialization Error $name: no char read";
    return "RFLINK: Initialization Error $name: no char read";
  } else {
    	Log 1, "RFLINK: Init OK";
  	  $hash->{STATE} = "Initialized";
  }
  #

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});

  Debug("RFLINK_DoInit...finished");
  return undef;
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
RFLINK_Read($)
{
  my ($hash) = @_;
  Debug("RFLINK_Read...");

  my $name = $hash->{NAME};

  my $char;

  my $data = DevIo_SimpleRead($hash);

  if(!defined($data) || length($data) == 0) {
    DevIo_Disconnected($hash);
    return "";
  }

  my $buffer = $hash->{PARTIAL};
  
  Log3 $name, 5, "MY_MODULE ($name) - received $data (buffer contains: $buffer)";
  
  # concat received data to $buffer
  $buffer .= $data;

  #see buffer my $rflinkcom_data = $hash->{PARTIAL};
  Log 5, "RFLINK/RAW: $buffer";

  while($buffer =~ m/\r\n/) {
    my $msg;
    ($msg,$buffer) = split("\r\n", $buffer, 2);
    $msg =~ s/ /_/g; ##replace blanks by underscore
    chomp $msg;
    Debug("RFLINK parse: readingsSingleUpdate with $msg");
    
    readingsSingleUpdate( $hash, "msg", $msg, 1 );
    RFLINK_Parse($hash, $hash, $name, $msg);
  }
  #Log 1, "RFLINK_Read END";

  Debug("RFLINK_Read...finished");

  $hash->{PARTIAL} = $buffer;
}


sub
RFLINK_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;

  Debug("RFLINK_Parse...");

  Log 5, "RFLINK_Parse1 '$rmsg'";

  my %addvals;
  # Parse only if message is different within 2 seconds 
  # (some Oregon sensors always sends the message twice, X10 security sensors even sends the message five times)
  if (("$last_rmsg" ne "$rmsg") || (time() - $last_time) > 1) { 
    Log 1, "RFLINK_Dispatch '$rmsg'";
    Debug("RFLINK_Dispatch '$rmsg'");
    my $test=$rmsg;
    
    if ( $test =~ m/^[0-9]{2};[0-9A-F]{2};Auriol_V3;.*/ ){
      Debug("RFLINK_Dispatch regex test '$test' MATCHED");  
    }else{
      Debug("RFLINK_Dispatch regex test '$test' DOES NOT MATCH");  
    }

    Debug("RFLINK Dispatch: $hash, $rmsg");
    Dispatch($hash, $rmsg, \%addvals); 

    $hash->{"${name}_MSGCNT"}++;
    $hash->{"${name}_TIME"} = TimeNow();
    $hash->{RAWMSG} = $rmsg;
  } else { 
    Debug("RFLINK_Dispatch '$rmsg' dup");
    Debug("<-duplicate->");
  }

  $last_rmsg = $rmsg;
  $last_time = time();

  Debug("RFLINK_Read...finished");

}


#####################################
sub
RFLINK_Ready($)
{
  my ($hash) = @_;
  Debug("RFLINK_Ready...");

  return DevIo_OpenDev($hash, 1, "RFLINK_Ready") if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

sub RFLINK_Attr {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  Debug ("RFLINK: Attr called with $cmd, $name, $aName, $aVal...");
}


1;

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
==============================

=begin html

<a name="RFLINK"></a>
<h3>RFLINK</h3>
<ul>
  This module is for the old <a href="http://www.rflinkcom.com">RFLINK</a> USB or LAN based 433 Mhz RF receivers and transmitters (order order code 80002 and others). It does not support the new RFXtrx433 transmitter because it uses a different protocol. See <a href="#RFXTRX">RFXTRX</a> for support of the RFXtrx433 transmitter.<br>
These receivers supports many protocols like Oregon Scientific weather sensors, RFXMeter devices, X10 security and lighting devices and others. <br>
  Currently the following parser modules are implemented: <br>
    <ul>
    <li> 41_OREGON.pm (see device <a href="#OREGON">OREGON</a>): Process messages Oregon Scientific weather sensors.
  See <a href="http://www.rflinkcom.com/oregon.htm">http://www.rflinkcom.com/oregon.htm</a> of
  Oregon Scientific weather sensors that could be received by the RFLINK receivers.
  Until now the following Oregon Scientific weather sensors have been tested successfully: BTHR918, BTHR918N, PCR800, RGR918, THGR228N, THGR810, THR128, THWR288A, WTGR800, WGR918. It will probably work with many other Oregon sensors supported by RFLINK receivers. Please give feedback if you use other sensors.<br>
    </li>
    <li> 42_RFXMETER.pm (see device <a href="#RFXMETER">RFXMETER</a>): Process RFLINK RFXMeter devices. See <a href="http://www.rflinkcom.com/sensors.htm">http://www.rflinkcom.com/sensors.htm</a>.</li>
    <li> 43_RFXX10REC.pm (see device <a href="#RFXX10REC">RFXX10REC</a>): Process X10 security and X10 lighting devices. </li>
    </ul>
  <br>
  Note: this module requires the Device::SerialPort or Win32::SerialPort module
  if the devices is connected via USB or a serial port.
  <br><br>
 <a name="RFLINKdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RFLINK &lt;device&gt; [noinit] </code><br>
  </ul>
    <br>
    USB-connected (80002):<br><ul>
      &lt;device&gt; specifies the USB port to communicate with the RFLINK receiver.
      Normally on Linux the device will be named /dev/ttyUSBx, where x is a number.
      For example /dev/ttyUSB0.<br>
      <br>
      Example: <br>
    <code>define RFLINKUSB RFLINK /dev/ttyUSB0</code>
      <br>
     </ul>
    <br>
    Network-connected devices:
    <br><ul>
    &lt;device&gt; specifies the host:port of the device. E.g.
    192.168.1.5:10001
    </ul>
    <ul>
    noninit is optional and issues that the RFLINK device should not be
    initialized. This is useful if you share a RFLINK device. It is also useful
    for testing to simulate a RFLINK receiver via netcat or via FHEM2FHEM.
      <br>
      <br>
      Example: <br>
    <code>define RFLINKTCP RFLINK 192.168.1.5:10001</code>
    <br>
    <code>define RFLINKTCP2 RFLINK 192.168.1.121:10001 noinit</code>
      <br>
    </ul>
    <br>
  <ul>
    <li><a href="#attrdummy">dummy</a></li><br>
    <li>longids<br>
        Comma separated list of device-types for RFLINK that should be handled using long IDs. This additional ID is a one byte hex string and is generated by the Oregon sensor when is it powered on. The value seems to be randomly generated. This has the advantage that you may use more than one Oregon sensor of the same type even if it has no switch to set a sensor id. For example the author uses two BTHR918N sensors at the same time. All have different deviceids. The drawback is that the deviceid changes after changing batteries. All devices listed as longids will get an additional one byte hex string appended to the device name.<br>
Default is to use long IDs for all devices.
      <br><br>
      Examples:<PRE>
# Do not use any long IDs for any devices:
attr RFLINKUSB longids 0
# Use any long IDs for all devices (this is default):
attr RFLINKUSB longids 1
# Use longids for BTHR918N devices.
# Will generate devices names like BTHR918N_f3.
attr RFLINKUSB longids BTHR918N
# Use longids for TX3_T and TX3_H devices.
# Will generate devices names like TX3_T_07, TX3_T_01 ,TX3_H_07.
attr RFLINKUSB longids TX3_T,TX3_H</PRE>
    </li><br>
  </ul>
</ul>

=end html
=cut
