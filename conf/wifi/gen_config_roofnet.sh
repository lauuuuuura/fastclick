#!/bin/sh
#
# generate a roofnet config file for click
# John Bicket
# 
#

DEV="ath1"
GATEWAY="false"
if [ -f /tmp/is_gateway ]; then
    GATEWAY="true"
fi
WIRELESS_MAC=`/home/roofnet/scripts/dev_to_mac ath0`
SUFFIX=`/home/roofnet/scripts/mac_to_ip $MAC`
SRCR_IP="5.$SUFFIX"
SRCR_NM="255.0.0.0"
SRCR_NET="5.0.0.0"
SRCR_BCAST="5.255.255.255"

/sbin/ifconfig $DEV txqueuelen 5
ifconfig $DEV up
echo '804' >  /proc/sys/net/$DEV/dev_type
/sbin/modprobe tun > /dev/null 2>&1

MODE="g"
PROBES="2 60 2 1500 4 1500 11 1500 22 1500"
#    $probes = "2 60 12 60 2 1500 4 1500 11 1500 22 1500 12 1500 18 1500 24 1500 36 1500 48 1500 72 1500 96 1500";
srcr_es_ethtype="0941";        # broadcast probes
srcr_forwarder_ethtype="0943"; # data
srcr_ethtype="0944";           # queries and replies
srcr_gw_ethtype="092c";        # gateway ads


echo "rates :: AvailableRates(DEFAULT 2 4 11 12 18 22 24 36 48 72 96 108,
$WIRELESS_MAC 2 4 11 12 18 22 24 36 48 72 96 108);
";

#    print "rates :: AvailableRates(DEFAULT 2 4 11 22);\n\n";

SRCR_FILE="srcr.click"
if [ ! -f $SRCR_FILE ]; then
    # ok, try srcr.click
    SRCR_FILE="/home/roofnet/click/conf/wifi/srcr.click"
fi

if [ ! -f $SRCR_FILE ]; then
    echo "couldn't find srcr.click: tried srcr.click, $SRCR_FILE";
    exit 1;
fi

cat $SRCR_FILE


echo "
control :: ControlSocket(\"TCP\", 7777);
chatter :: ChatterSocket(\"TCP\", 7778);


// has one input and one output
// takes and spits out ip packets

elementclass LinuxHost {
    \$dev, \$ip, \$nm, \$mac |
    input -> ToHost(\$dev);
    FromHost(\$dev, \$ip/\$nm, ETHER \$mac) -> output;
}

// has one input and one output
// takes and spits out ip packets
elementclass LinuxIPHost {
    \$dev, \$ip, \$nm |

  input -> KernelTun(\$ip/\$nm, MTU 1500, DEV_NAME \$dev) 
  -> MarkIPHeader(0)
  -> CheckIPHeader()
  -> output;

}

elementclass SniffDevice {
    \$device, \$promisc|
	// we only want txf for NODS packets
	// ether[2:2] == 0x1200 means it has an ath_rx_radiotap header (it is 18 bytes long)
	// ether[2:2] == 0x1000 means it has an ath_tx_radiotap header (it is 16 bytes long)
	// ether[18] == 0x08 means NODS
  from_dev :: FromDevice(\$device, 
			 PROMISC \$promisc) 
  -> output;
  input -> to_dev :: ToDevice(\$device);
}

sniff_dev :: SniffDevice($DEV, false);

sched :: PrioSched()
-> set_power :: SetTXPower(POWER 60)
-> athdesc_encap :: AthdescEncap()
//-> radiotap_encap :: RadiotapEncap()
-> sniff_dev;

route_q :: FullNoteQueue(10) 
-> [0] sched;

data_q :: FullNoteQueue(10)
-> data_static_rate :: SetTXRate(RATE 2)
-> data_madwifi_rate :: MadwifiRate(OFFSET 4,
			       ALT_RATE true,
			       RT rates,
			       ACTIVE true)
-> data_arf_rate :: AutoRateFallback(OFFSET 4,
				STEPUP 25,
				RT rates,
				ACTIVE false)
-> data_probe_rate :: ProbeTXRate(OFFSET 4,
			     WINDOW 5000,
			     RT rates,
			     ACTIVE false)

-> [1] sched;

Idle -> [1] data_probe_rate;
Idle -> [1] data_madwifi_rate;
Idle -> [1] data_arf_rate;



srcr :: srcr_ett($SRCR_IP, $SRCR_NM, $WIRELESS_MAC, $GATEWAY, 
		 \"$PROBES\");

// make sure this is listed first so it gets tap0
srcr_host :: LinuxIPHost(srcr, $SRCR_IP, $SRCR_NM)
->  srcr_cl :: IPClassifier(dst net 10.0.0.0/8, -);

ap_to_srcr :: SRDestCache();

srcr_cl [0] -> [0] ap_to_srcr [0] -> [1] srcr;
srcr_cl [1] -> [1] srcr;

route_encap :: WifiEncap(0x0, 00:00:00:00:00:00)
->  route_q;
data_encap :: WifiEncap(0x0, 00:00:00:00:00:00)
-> data_q;



srcr [0] -> route_encap;   // queries, replies
srcr [1] -> route_encap;   // bcast_stats
srcr [2] -> data_encap;    // data
srcr [3] -> srcr_cl2 :: IPClassifier(src net 10.0.0.0/8, -); //data to me

srcr_cl2 [0] -> [1] ap_to_srcr [1] -> srcr_host; 
srcr_cl2 [1] -> srcr_host; // data to me


sniff_dev 
-> athdesc_decap :: AthdescDecap()
-> phyerr_filter :: FilterPhyErr()
//-> PrintWifi(fromdev)
-> beacon_cl :: Classifier(0/80, //beacons
			    -)
-> bs :: BeaconScanner(RT rates)
-> Discard;

beacon_cl [1]
-> Classifier(0/08%0c) //data
-> tx_filter :: FilterTX()
-> dupe :: WifiDupeFilter() 
-> WifiDecap()
-> HostEtherFilter($WIRELESS_MAC, DROP_OTHER true, DROP_OWN true) 
-> rxstats :: RXStats()
-> ncl :: Classifier(12/09??, -);


ncl [0] -> srcr;

ncl[1]  -> Discard;

tx_filter [1] 
//-> PrintWifi(txf)
-> txf_t2 :: Tee(3);

txf_t2 [0] -> [1] data_arf_rate;
txf_t2 [1] -> [1] data_madwifi_rate;
txf_t2 [2] -> [1] data_probe_rate;


";
