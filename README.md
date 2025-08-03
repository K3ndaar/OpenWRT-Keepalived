# Overview
This configuration will setup VRRP between two OpenWRT routers.

Most of existing configurations have at least two interfaces, but if you're 
wondering about VRRP, chances are that you're having at least three (lan, iot, wan).

Also, this guide assumes that your two routers are behind a carrier router.

This document will guide you thorugh the configuration of ```keepalived``` and ```dnsmasq``` in both routers.

Since in OpenWRT every startup script is rebuilding actual configuration
files from scratch, we will tell UCI to use custom ```keepalived``` configuration (a pure UCI configuration is harder to setup and won't allow some group attributes) and ```dnsmasq``` scripts to trigger the leases synchonization.

Usually VRRP uses multicast groups to communcate between nodes, but multicast is sometimes not well managed by home network devices.
This guide will use unicast packets. Anyway, YMMV.

# Keepalived configuration
## Setup
Follow these steps, detailed below, to setup this keepalived configuration:
1. Install the required OpenWRT packages
1. Copy all the ```keepalived/scripts``` files in the router's
```/etc/keepalived/scripts/``` directory.
1. Compile ```/etc/keepalived/keepalived.conf``` file according to your configuration
1. Make all the changes in ```/etc/keepalived/scripts/.env``` required by your setup
1. Set ```/etc/config/keepalive``` to use our config file
1. Start keepalived on master
1. Start keepalived on backup
1. Test the swicth while doing something that involves networking, especially
towards the internet. (be aware that streaming usually have buffers that may masquerade transient lack of connection. VRRP switch must be almost immedate)

### Packages
You will need two pakckages: ```keepalived``` and ```luci-app-keepalived```:
```
opkg update
opkg install keepalived luci-app-keepalived
```
The former is the actual daemon, the latter is a convenent LUCI app to monitor
and do some small changes. 

***We won't rely on LUCI to configure ```keepalived```***.

LUCI package is mailny installed forthe convenient monitor in Status > VRRP menu.
If you start configuring in LUCI, then the config file will be overwritten and you will lose access to the ```keepalived.conf``` file we're about to create.

## Configuration file
The configuration file is in ```/etc/keepalived/keepalived.conf```.

The following sections must be created.

### Global definitions
This contains global definitions, the most important is the ```router_id```. Here's an example:


#### ```/etc/keepalived/keepalived.conf```
```
global_defs {
	script_user root
	enable_script_security
	process_names

	router_id openwrt-01
}
```

If you want to use multicast, add the following line to global_defs (using standard VRRP multicast group):
```
vrrp_mcast_group4 224.0.0.18
```


### Scripts
We will rely on a script to check if our carrier router is available.

Why the carrier router and not some IP address? Well, in case of carrier fault we don't want to trigger switches that may affect the internal network. On the other hand if we can't reach our carrier router could be because of a local OpenWRT router fault, so it's worth switching.

#### ```/etc/keepalived/keepalived.conf```
```
vrrp_script chk_wan_connectivity {
    script   "/etc/keepalived/scripts/check_wan_connectivity.sh"
    interval   5      # Run every 5 seconds
    weight   -30      # Lower priority by 30 if script fails (a strong trigger for failover)
    fall       2      # Fail after 2 consecutive failures
    rise       2      # Succeed after 2 consecutive successes
}
```
Should this script fail, the weight of the node will drop by 30, potentially triggering the role switch. It must fail twice - fail equal to 2 - before triggering the switch: this means at least 10 seconds of outage, to avoid transient errors. The same for returing to the original weight, specified by the rise parameter.


### VRRP Instances
We will define a VRRP instance for every interface. Every instance must have its own interface, virtual ip address and virtual router.
Also we will track the interface. The failover scenario is that everything must move at the same time, even if a single interface fails. This will prevent issues with firewall rules that usually are meant to work with all interfaces active on the same router.

#### ```/etc/keepalived/keepalived.conf```
```
vrrp_instance VI_LAN {
    state MASTER          # BACKUP on the backup node
    priority 100          # 90 on the backup node

    debug 0
    advert_int 1
    garp_master_refresh 5
    garp_master_delay 1
    garp_master_repeat 1
    garp_master_refresh_repeat 1

    authentication {
        auth_type PASS
        auth_pass VERYstrongBUTshortPWD
    }

    virtual_router_id 1
    interface lan0
    virtual_ipaddress {
        192.168.100.1/24 dev lan0 label lan0:vip
    }

    track_interface {
        lan0
    }
    unicast_src_ip 192.168.100.2   # our ip address - change on other node
    unicast_peer {
      192.168.100.3                # other router ip address - change on other node
    }
}
```
Again, if you chose multicast, the avoid ```unicast_src_ip``` and ```unicast_peer```

You can add as many instances as you want. These vaules must be unique by instance
- ```virtual_router_id```
- ```interface```
- ```virtual_ipaddress```
- ```track_interface```

Be aware that the other node, which is usually the backup, must reflect the same 
configuration (same virtual_router_id, interface, virtual_ipaddress and so on)
except for:
- ```state```
- ```priority``` (we use 100 for master, 90 for backup and -30 for scripts to be sure to trigger the switch)
- ```unicast_src_ip```
- ```unicast_peer```

### VRRP Sync Group
This is the part where we tell keepalived that insances must be considered as a single object when it comes for switching.

#### ```/etc/keepalived/keepalived.conf```
```
vrrp_sync_group VG_FIREWALL {
    group {
        VI_LAN
        VI_IOT
        VI_WAN
    }
    track_script {
        chk_wan_connectivity
    } 
    # These notify scripts are the core of our orchestration.
    notify_master "/etc/keepalived/scripts/global_state_change.sh MASTER"
    notify_backup "/etc/keepalived/scripts/global_state_change.sh BACKUP"
    notify_fault "/etc/keepalived/scripts/global_state_change.sh FAULT"
}
```
Notice that the group contains all the instances and that there's a track script:
this is the one that will trigger the switch even if we have all interafaces up
and running but we can't reach the carrier router. It will run, according to
the parameter we specified above, every 5 seconds.

Then we have the notify scripts: these will run when the node transition from
its current state to MASTER, BACKUP or FAULT.

Fault is when there was some issue (like we lost link on one of the instances).
The loss of connectivity, in this scenario, will demote the master node to the
BACKUP state, because of the weight loss.

## UCI configuration
We need UCI to use our configuration file instead of rebuilding a new one every
time it starts.

The keepalived process is using ```/tmp/keepalived.conf``` as config file, and
we need this to be a link to our configuration. UCI takes care of the link, if
properly configured

#### ```/etc/config/keepalived```
```
config globals 'globals'
	option alt_config_file "/etc/keepalived/keepalived.conf"
```

This option is not managed by LUCI, hence the advice not to use LUCI to configure
keepalived. Furthermore we use notification from Sync Group, another thing LUCI
is not able to manage. Let's avoid configuring with LUCI for now, and just use
the monitoring page, which is great!

## Keepalived scripts
### ```.env``` file
All the scripts are working with ```/etc/keepalived/scripts/.env``` file as source for personalization.
An example file is included in the repository: copy it and make your changes.
### global_state_change.sh
This is the main script responsible for all the actions when the state of the
node changes. it is called within ```keepalived.conf``` as notify script within
the Sync Group configuration.

Accepts one parameter: MASTER, BACKUP or FAULT.

It operates on VPNs (wireguard in the examples) activating them if node is MASTER,
deactivating if is BACKUP or FAULT.
The same happend with DHCP.

The script also generates ```/tmp/keepalived_status``` used by dhcp sync script.

### sync_config_daemon_trigger.sh
Invoked by ```global_state_change.sh```, it triggers the sync daemon and manages
its lifecycle.

You should not need to change this file.

### sync_config_daemon.sh
This script is responsible for file synchronization.

Files and directories to be synchronized are listed in the ```.env``` file.

It works using ```inotifywait``` command that triggers remote synchronization
upon changes in the monitored files and directory.

If changes happens to dhcp or firewall, it triggers the reload on remote.

### dhcp_sync_leases.sh
It's the script responsible for dhcp leases updates.
It works only on the master (checks ```/tmp/keepalived_status``` to understand
the role of the system), copies the lease file and triggers a reload of dnsmasq
on remote.

Since ```global_state_changes.sh``` disabled the dhcp on BACKUP nodes, this
won't create issues.

### check_wan_connectivity.sh
This script is invoked by ```keepalived``` as tracking script.

By default it checks what's in ```WAN_CHECK_IP``` variable. if it's pingable,
then everything is ok, if not, depending on the parameters in 
```keepalived.conf``` file, it will trigger the switch to the other router.

### utils.sh
Utlity functions used by other scripts.



# Conclusion
Even if it's not straightfowrard to configure, VRRP with keepalived is a fast, 
rather simple way to have redundant OpenWRT router to work together ensuring 
high available network connection, even at home.
