# Release Notes

## Version 1.0 - July 2024

| Component | Version |
| --------- | ------- |
| Base OS   | Ubuntu 22.04 LTS (for x86-64) |
| [UERANSIM](https://github.com/aligungr/UERANSIM)  | v3.2.6  |

# Overview

This appliance includes a pre-installed version of the [UERANSIM](https://github.com/aligungr/UERANSIM) 5G UE and RAN (gNodeB) simulator. This appliance can be used for creating a simulated 5G network. A complete scenario includes the deployment of a 5G core as described in the next sections. The appliance includes two major components:

* gNodeB - component which emulates cellular base station (gNodeB) in the RAN and performs communication with 5G Core components.
* UE emulator - software component which emulates 5G user equipment, i.e. cellular phone.


## Architecture of the 5G network

The following diagram shows the architecture of the target scenario, it consists of the following components:

* The UERANSIM appliance that will simulate the gNodeB and UE elements
* A OneKE kubernetes cluster that will be used to simplify the deployment of the 5G core
* A 5G network core, in our case we'll be using [Open5GS](https://open5gs.org/)

In the next section we will describe how to manually deploy this architecture.

```
    ┌──────────────────┐
    │UERANSIM Appliance│
    │ ┌────┐   ┌─────┐ │
    │ │ UE │   │ gNB │ │
    │ └────┘   └─────┘ │
    └─────────┬────────┘
              │
              │ Public Network
              │
┌──  ──  ──  ─┼──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──┐
              │                                  OnKE Kubernetes Cluster
│  ┌──────────┴───────────┐                                              │
   │ VNF - Virtual Router │
│  └──┬───────────────────┘                                              │
      │
│     │                                                                  │
      │                                           Private Network
│     └──| MetalLB IP pool |────────┬──────────────────────┬─────        │
               │                    │                      │
│              │                    │                      │             │
               │                    │                      │
│        ┌─────┴────┐      ┌────────┴────────┐      ┌──────┴─────────┐   │
         │k8s Master│      │ k8s Worker Node │      │k8s Storage Node│
│        └──────────┘      │ ┌────────────┐  │      │  ┌───────────┐ │   │
                           │ │Open5Gs pods│  │      │  │MongodB PVC│ │
│                          │ └────────────┘  │      │  └───────────┘ │   │
                           └─────────────────┘      └────────────────┘
└──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ──  ───   ──┘

```

# Requirements

* Working OpenNebula installation, version >= 6.4
* [OneFlow](https://docs.opennebula.io/stable/management_and_operations/multivm_service_management/overview.html) and [OneGate](https://docs.opennebula.io/stable/management_and_operations/multivm_service_management/onegate_usage.html) for multi-node orchestration.
* Two virtual networks in your OpenNebula cluster (please refer to the architecture diagram).
  - *Public* network to interconnect the RAN/UE with the OneKE
  - *Private* network to interconnect the OneKE components.

# Step 1. Deploy OneKE cluster

## Download OneKE from Marketplace

We'll be using OneKE version 1.29, the airgapped variant. You can use Susntone interface or CLI. As an example, using the CLI the procedure will look like this:

```shell
onemarketapp export -d default 'Service OneKE 1.29 Airgapped' OneKE1.29
```

Wait for the images to download and be ready. All the associated resources would look like this:

```shell
> onetemplate list
  ID USER     GROUP    NAME                   REGTIME
 151 oneadmin oneadmin OneKE1.29-storage-2    07/22 13:52:17
 150 oneadmin oneadmin OneKE1.29-master-1     07/22 13:52:17
 149 oneadmin oneadmin OneKE1.29-vnf-0        07/22 13:52:17

> oneimage list
  ID USER     GROUP    NAME                                  DATASTORE     SIZE TYPE PER STAT RVMS
  38 oneadmin oneadmin OneKE1.29-storage-2-b3589b800e-1      default        10G OS    No rdy     0
  37 oneadmin oneadmin OneKE1.29-storage-2-63d7b78328-0      default        25G OS    No rdy     0
  36 oneadmin oneadmin OneKE1.29-master-1-86152b69cb-0       default        25G OS    No rdy     0
  35 oneadmin oneadmin OneKE1.29-vnf-0                       default         2G OS    No rdy     0

> oneflow-template list
  ID USER     GROUP    NAME                 REGTIME
  17 oneadmin oneadmin OneKE1.29            07/22 13:52:17
```

## Update OneFlow and VM templates

* Update the cardinality of the storage role of OneKE to 3
```shell
> oneflow-template update OneKE1.29
...
    {
      "name": "storage",
      "parents": [
        "vnf"
      ],
      "cardinality": 3,
...
```
* Update the `CPU_MODEL` the OneKE master/worker VM templates
```shell
> onetemplate update OneKE1.29-master-1
...
CPU_MODEL=[
  MODEL="host-passthrough" ]
...
```

## Instantiate OneKE

We'll be using longhorn persistent storage as it is required by the MongoDB pod deployed by Open5GS. Additionally, we'll need MetalLB to expose a full IP for the AMF LoadBalancer service, as this requires SCTP trasnport. Gather the following information:

* Virtual Network ID of the public network (``0`` in the example below)
* Virtual Network ID of the OneKE private network (``1`` in the example below)
* An IP range from the private network for MetalLB (``192.168.150.50-192.168.150.80`` in the example below). We recommend that you put this IPs on hold in the network so they are not used by any worker or storage node.

Now you can create a file with all this configuration parameters.

 :warning: Note ``network_values`` and ``ONEAPP_K8S_METALLB_RANGE`` attributes **need to be updated** with your own information:

```shell
$ cat >./OneKE5G-instantiate <<'EOF'
{
    "name": "OneKE-5G",
    "networks_values": [
        {"Public": {"id": "0"}},
        {"Private": {"id": "1"}}
    ],
    "custom_attrs_values": {
        "ONEAPP_VROUTER_ETH0_VIP0": "",
        "ONEAPP_VROUTER_ETH1_VIP0": "",

        "ONEAPP_RKE2_SUPERVISOR_EP": "ep0.eth0.vr:9345",
        "ONEAPP_K8S_CONTROL_PLANE_EP": "ep0.eth0.vr:6443",
        "ONEAPP_K8S_EXTRA_SANS": "localhost,127.0.0.1,ep0.eth0.vr,${vnf.TEMPLATE.CONTEXT.ETH0_IP}",

        "ONEAPP_K8S_MULTUS_ENABLED": "NO",
        "ONEAPP_K8S_MULTUS_CONFIG": "",
        "ONEAPP_K8S_CNI_PLUGIN": "calico",
        "ONEAPP_K8S_CNI_CONFIG": "",
        "ONEAPP_K8S_CILIUM_RANGE": "",

        "ONEAPP_K8S_METALLB_ENABLED": "YES",
        "ONEAPP_K8S_METALLB_CONFIG": "",
        "ONEAPP_K8S_METALLB_RANGE": "192.168.150.50-192.168.150.80",

        "ONEAPP_K8S_LONGHORN_ENABLED": "YES",
        "ONEAPP_STORAGE_DEVICE": "/dev/vdb",
        "ONEAPP_STORAGE_FILESYSTEM": "xfs",

        "ONEAPP_K8S_TRAEFIK_ENABLED": "YES",
        "ONEAPP_VNF_HAPROXY_INTERFACES": "eth0",
        "ONEAPP_VNF_HAPROXY_REFRESH_RATE": "30",
        "ONEAPP_VNF_HAPROXY_LB0_PORT": "9345",
        "ONEAPP_VNF_HAPROXY_LB1_PORT": "6443",
        "ONEAPP_VNF_HAPROXY_LB2_PORT": "443",
        "ONEAPP_VNF_HAPROXY_LB3_PORT": "80",

        "ONEAPP_VNF_DNS_ENABLED": "YES",
        "ONEAPP_VNF_DNS_INTERFACES": "eth1",
        "ONEAPP_VNF_DNS_NAMESERVERS": "1.1.1.1,8.8.8.8",
        "ONEAPP_VNF_NAT4_ENABLED": "YES",
        "ONEAPP_VNF_NAT4_INTERFACES_OUT": "eth0",
        "ONEAPP_VNF_ROUTER4_ENABLED": "YES",
        "ONEAPP_VNF_ROUTER4_INTERFACES": "eth0,eth1"
    }
}
EOF
```

Now create your OneKE cluster
```shell
> oneflow-template instantiate OneKE1.29 OneKE5G
ID: 19
```

The deployment of the full cluster will take several minutes. Wait till the flow reaches the ``RUNNING`` state:
```shell
> oneflow list
  ID USER     GROUP    NAME                  STARTTIME STAT
  19 oneadmin oneadmin OneKE-5G         07/22 14:23:03 RUNNING
```

## Configure your Kubernetes Client

We'll need to interact with the Kubernetes cluster. For your convenience grab the kubeconfig file using the master VM (``master_0_(service_19)`` in our example):
```shell
onevm show 'master_0_(service_19)' --json | jq -r '.VM.USER_TEMPLATE.ONEKE_KUBECONFIG|@base64d' > oneke.kubeconfig
```

Now you should be able to check that all nodes are ready in your k8s cluster:

```shell
>  kubectl --kubeconfig oneke.kubeconfig get nodes
NAME                     STATUS   ROLES                       AGE     VERSION
oneke-ip-192-168-150-2   Ready    control-plane,etcd,master   10m     v1.29.4+rke2r1
oneke-ip-192-168-150-3   Ready    <none>                      5m47s   v1.29.4+rke2r1
oneke-ip-192-168-150-4   Ready    <none>                      5m55s   v1.29.4+rke2r1
oneke-ip-192-168-150-5   Ready    <none>                      5m52s   v1.29.4+rke2r1
oneke-ip-192-168-150-6   Ready    <none>                      6m4s    v1.29.4+rke2r1
```

# Step 2. Deploy Open5GS core
## Create a configuration file for the service
We'll be setting some values for the AMF and UPF components. These settings need to be consistent with that used by the UERANSIM appliance below. For AMF configuration the key parameters are the mobile network configuration (the Mobile Country Code value ``mcc`` and the Mobile Network Code value ``mnc``):
```yaml
      - plmn_id:
          mcc: "999"
          mnc: "70"
```

The UPF configuration is defined by the following block:
```yaml
upf:
  config:
    upf:
      gtpu:
        advertise: "192.168.150.60"
  services:
    gtpu:
      type: LoadBalancer
      loadBalancerIP: "192.168.150.60"
```
The key parameter here is the gptu configuration. The deployment of the Open5GS core uses a k8s service of type LoadBalancer to expose UPF endpoint (default setting in the chart is the ClusterIP). This IP is used to setup GTP tunnels between UE and UPF.

:warning: Select the IP within the MetalLB range defined above

Also in the Open5Gs values file includes a sample UE configuration which is pre-populated both at 5G core and UERANSIM appliance:

| Attribute | Value |
|-------|-------|
| imsi  | 999700000000001 |
| key   | 465B5CE8B199B49FAA5F0A2EE238A6BC |
| opc   | E8ED289DEBA952E4283B54E88E6183CA |
| apn   | “internet” |
| sst   | 1 |
| sd    | "0x111111" |

The complete file is the following:
```shell
cat > 5gs_values.yaml << EOF
mongodb:
  persistence:
    size: 3Gi

hss:
  enabled: false

mme:
  enabled: false

pcrf:
  enabled: false

smf:
  config:
    pcrf:
      enabled: false

sgwc:
  enabled: false

sgwu:
  enabled: false

upf:
  config:
    upf:
      gtpu:
        advertise: "192.168.150.60"
  services:
    gtpu:
      type: LoadBalancer
      loadBalancerIP: "192.168.150.60"

amf:
  services:
    ngap:
      type: LoadBalancer
  config:
    guamiList:
      - plmn_id:
          mcc: "999"
          mnc: "70"
        amf_id:
          region: 2
          set: 1
    taiList:
      - plmn_id:
          mcc: "999"
          mnc: "70"
        tac: [1]
    plmnList:
      - plmn_id:
          mcc: "999"
          mnc: "70"
        s_nssai:
          - sst: 1
            sd: "0x111111"

nssf:
  config:
    nsiList:
      - uri: ""
        sst: 1
        sd: "0x111111"

webui:
  ingress:
    enabled: false

populate:
  enabled: true
  initCommands:
  - open5gs-dbctl add_ue_with_slice 999700000000001 465B5CE8B199B49FAA5F0A2EE238A6BC E8ED289DEBA952E4283B54E88E6183CA internet 1 111111
EOF
```
## Create the Open5GS core

With the above input file we can simply install the Open5GS helm chart:
```shell
helm upgrade --install open5gs oci://registry-1.docker.io/gradiant/open5gs --version 2.2.2 --namespace open5gs --create-namespace --values ./5gs_values_template.yaml --kubeconfig oneke.kubeconfig
Release "open5gs" does not exist. Installing it now.
Pulled: registry-1.docker.io/gradiant/open5gs:2.2.2
Digest: sha256:65f8e0790239e7a353794e2285e992020b76314b574f952ceb17ddb782b5244e
NAME: open5gs
LAST DEPLOYED: Mon Jul 22 15:54:44 2024
NAMESPACE: open5gs
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

And wait till the service is ready:
```shell
>  kubectl --kubeconfig oneke.kubeconfig -n open5gs get pod
NAME                                READY   STATUS    RESTARTS      AGE
open5gs-amf-669c66f9f9-qqc52        1/1     Running   0             2m40s
open5gs-ausf-54c46f4ddc-gpl2j       1/1     Running   0             2m40s
open5gs-bsf-6bc55556fc-vfhff        1/1     Running   0             2m40s
open5gs-mongodb-55598f5ddc-zm4dt    1/1     Running   0             2m40s
open5gs-nrf-6c96798bbb-v8c2m        1/1     Running   0             2m40s
open5gs-nssf-687ff6c8b7-892qk       1/1     Running   0             2m40s
open5gs-pcf-7b4576c5c7-vs5v9        1/1     Running   4 (83s ago)   2m39s
open5gs-populate-76576f4f4b-ftzng   1/1     Running   0             2m40s
open5gs-scp-d6cc9dc48-cxnmb         1/1     Running   0             2m39s
open5gs-smf-7c9f8dd876-v58ph        1/1     Running   0             2m40s
open5gs-udm-7c8b68c5fc-4nd64        1/1     Running   0             2m40s
open5gs-udr-f7b6b5b6d-686z8         1/1     Running   4 (81s ago)   2m40s
open5gs-upf-d5bdf6b68-kn2qx         1/1     Running   0             2m40s
open5gs-webui-97f5c9559-lgbgk       1/1     Running   0             2m40s
```

# Step 3. Deploy UERANSIM
## Download the appliance from the community marketplace
```shell
onemarketapp export -d default 'UERANSIM' UERANSIM
```
## Configure UERANSIM

### Get AMF service IP

Get the open5gs service information, we are interested in the amf EXTERNAL-IP (192.168.150.50 in our case):
```shell
kubectl get svc -n open5gs --kubeconfig oneke.kubeconfig
NAME               TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)            AGE
open5gs-amf-ngap   LoadBalancer   10.43.248.200   192.168.150.50   38412:30178/SCTP   6m14s
open5gs-amf-sbi    ClusterIP      10.43.150.64    <none>           7777/TCP           6m14s
open5gs-ausf-sbi   ClusterIP      10.43.250.188   <none>           7777/TCP           6m14s
open5gs-bsf-sbi    ClusterIP      10.43.106.210   <none>           7777/TCP           6m14s
open5gs-mongodb    ClusterIP      10.43.70.105    <none>           27017/TCP          6m14s
open5gs-nrf-sbi    ClusterIP      10.43.153.179   <none>           7777/TCP           6m14s
open5gs-nssf-sbi   ClusterIP      10.43.25.213    <none>           7777/TCP           6m14s
open5gs-pcf-sbi    ClusterIP      10.43.105.24    <none>           7777/TCP           6m14s
open5gs-scp-sbi    ClusterIP      10.43.147.102   <none>           7777/TCP           6m14s
open5gs-smf-gtpc   ClusterIP      10.43.58.176    <none>           2123/UDP           6m14s
open5gs-smf-gtpu   ClusterIP      10.43.69.7      <none>           2152/UDP           6m14s
open5gs-smf-pfcp   ClusterIP      10.43.98.20     <none>           8805/UDP           6m14s
open5gs-smf-sbi    ClusterIP      10.43.115.58    <none>           7777/TCP           6m14s
open5gs-udm-sbi    ClusterIP      10.43.211.200   <none>           7777/TCP           6m14s
open5gs-udr-sbi    ClusterIP      10.43.14.108    <none>           7777/TCP           6m14s
open5gs-upf-gtpu   LoadBalancer   10.43.100.51    192.168.150.60   2152:32400/UDP     6m14s
open5gs-upf-pfcp   ClusterIP      10.43.191.251   <none>           8805/UDP           6m14s
open5gs-webui      ClusterIP      10.43.203.254   <none>           9999/TCP           6m14s
```

### Get the VNF public IP
You can get this one by simply looking into the VM properties (172.20.0.3 in our case):
```shell
> onevm show 'vnf_0_(service_19)'
VIRTUAL MACHINE 162 INFORMATION
ID                  : 162
NAME                : vnf_0_(service_19)
USER                : oneadmin
GROUP               : oneadmin
STATE               : ACTIVE
LCM_STATE           : RUNNING
LOCK                : None
RESCHED             : No
HOST                : localhost
CLUSTER ID          : 0
CLUSTER             : default
START TIME          : 07/22 15:10:23
END TIME            : -
DEPLOY ID           : 25852006-121a-4313-93d6-143d7ca25ef4
...

VM NICS
 ID NETWORK              BRIDGE       IP              MAC               PCI_ID
  0 public               vbr0         172.20.0.3      02:00:ac:14:00:03
  1 k8s Network          onebr55      192.168.150.1   02:00:c0:a8:96:01

### Update the UERANSIM template and instantiate
We just need to input the above information so the UERANSIM appliance can auto-configure the UE and gNB services:
```shell
onetemplate update UERANSIM
...
CONTEXT=[
  NETWORK="YES",
  ONEAPP_UERAN_AMF_IP="192.168.150.50",
  ONEAPP_UERAN_CORE_SUBNET="192.168.150.0/24",
  ONEAPP_UERAN_NETWORK_MCC="999",
  ONEAPP_UERAN_NETWORK_MNC="70",
  ONEAPP_UERAN_VNF_IP="172.20.0.3",
  SET_HOSTNAME="$NAME",
  SSH_PUBLIC_KEY="$USER[SSH_PUBLIC_KEY]" ]
...
```

:warning: Update ``ONEAPP_UERAN_AMF_IP``, ``ONEAPP_UERAN_VNF_IP`` and ``ONEAPP_UERAN_CORE_SUBNET`` with the values you gather from your deployment.

Now simple instantiate the template
```shell
onetemplate instantiate UERANSIM --name UERANSIM
ID: 179
```

# Step 4. Verification and troubleshooting

You can now login in the UERANSIM through SSH:
```shell
> onevm ssh UERANSIM
Warning: Permanently added '172.20.0.4' (ED25519) to the list of known hosts.
Welcome to Ubuntu 22.04.4 LTS (GNU/Linux 5.15.0-116-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro
...
    ___   _ __    ___
   / _ \ | '_ \  / _ \   OpenNebula Service Appliance
  | (_) || | | ||  __/
   \___/ |_| |_| \___|

 All set and ready to serve 8)

Last login: Tue Jul 23 07:07:06 2024 from 172.20.0.1
```

You should see the UERANSIM processes
```shell
> ps -celfa | grep ueran
0 S root        1725    1645 TS   19 - 172698 do_sel 07:09 pts/0   00:00:12 /opt/UERANSIM/build/nr-gnb -c /opt/UERANSIM/config/ueransim-gnb.yaml
0 S root        1737    1645 TS   19 - 137609 do_sel 07:09 pts/0   00:00:15 /opt/UERANSIM/build/nr-ue -c /opt/UERANSIM/config/ueransim-ue.yaml
```

As well as a tun device for the UE Internet connection if the data plane (U-plane) session between UE and 5G core has been successfully established:

```shell
> ip address
...
3: uesimtun0: <POINTOPOINT,PROMISC,NOTRAILERS,UP,LOWER_UP> mtu 1400 qdisc fq_codel state UNKNOWN group default qlen 500
    link/none
    inet 10.45.0.2/32 scope global uesimtun0
       valid_lft forever preferred_lft forever
    inet6 fe80::1a57:180d:91eb:116d/64 scope link stable-privacy
       valid_lft forever preferred_lft forever
```

At this point it should be possible to test data plane connection using regular ping over tun interface:
```shell
> ping -c3 -I uesimtun0 8.8.8.8
PING 8.8.8.8 (8.8.8.8) from 10.45.0.2 uesimtun0: 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=115 time=11.5 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=115 time=9.83 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=115 time=10.5 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2004ms
rtt min/avg/max/mdev = 9.830/10.596/11.458/0.668 ms
```

If you the UE tun interface is missing, most likely the connection between RAN and 5G core wasn’t successful. First it is recommended to look into gNodeB logs. During the initial startup, gNodeB logs are forwarded to ``/var/log/gnb.log``. The key item to investigate within gNB log is the status of the SCTP session between gNB and 5G core AMF.

Below is the example of successful session establishment:
```
UERANSIM v3.2.6
[2024-07-23 07:09:30.783] [sctp] [info] Trying to establish SCTP connection... (192.168.150.50:38412)
[2024-07-23 07:09:30.787] [sctp] [info] SCTP connection established (192.168.150.50:38412)
[2024-07-23 07:09:30.787] [sctp] [debug] SCTP association setup ascId[3]
[2024-07-23 07:09:30.788] [ngap] [debug] Sending NG Setup Request
[2024-07-23 07:09:30.796] [ngap] [debug] NG Setup Response received
[2024-07-23 07:09:30.796] [ngap] [info] NG Setup procedure is successful
```

Sometimes in the logs it is explicitly mentioned that SCTP connection can’t be established. In this case the most common cause is the data plane connectivity between UERANSIM appliance and AMF subnetwork. Check that routes are in place:
```shell
> ip route
...
192.168.150.0/24 via 172.20.0.3 dev eth0
```

During initial startup, UE logs are forwarded to /var/log/ue.log. Below is example of successful session establishment between the UE and 5G core:
```
UERANSIM v3.2.6
[2024-07-23 07:09:46.928] [nas] [info] UE switches to state [MM-DEREGISTERED/PLMN-SEARCH]
[2024-07-23 07:09:46.929] [rrc] [debug] UE[1] new signal detected
[2024-07-23 07:09:46.931] [rrc] [debug] New signal detected for cell[1], total [1] cells in coverage
[2024-07-23 07:09:46.931] [nas] [info] Selected plmn[999/70]
[2024-07-23 07:09:46.931] [rrc] [info] Selected cell plmn[999/70] tac[1] category[SUITABLE]
[2024-07-23 07:09:46.931] [nas] [info] UE switches to state [MM-DEREGISTERED/PS]
[2024-07-23 07:09:46.931] [nas] [info] UE switches to state [MM-DEREGISTERED/NORMAL-SERVICE]
[2024-07-23 07:09:46.932] [nas] [debug] Initial registration required due to [MM-DEREG-NORMAL-SERVICE]
[2024-07-23 07:09:46.932] [nas] [debug] UAC access attempt is allowed for identity[0], category[MO_sig]
[2024-07-23 07:09:46.932] [nas] [debug] Sending Initial Registration
[2024-07-23 07:09:46.934] [nas] [info] UE switches to state [MM-REGISTER-INITIATED]
[2024-07-23 07:09:46.934] [rrc] [debug] Sending RRC Setup Request
[2024-07-23 07:09:46.934] [rrc] [info] RRC Setup for UE[1]
[2024-07-23 07:09:46.935] [rrc] [info] RRC connection established
[2024-07-23 07:09:46.935] [rrc] [info] UE switches to state [RRC-CONNECTED]
[2024-07-23 07:09:46.935] [nas] [info] UE switches to state [CM-CONNECTED]
[2024-07-23 07:09:46.935] [ngap] [debug] Initial NAS message received from UE[1]
[2024-07-23 07:09:46.951] [nas] [debug] Authentication Request received
[2024-07-23 07:09:46.952] [nas] [debug] Received SQN [0000000000E1]
[2024-07-23 07:09:46.952] [nas] [debug] SQN-MS [000000000000]
[2024-07-23 07:09:46.958] [nas] [debug] Security Mode Command received
[2024-07-23 07:09:46.958] [nas] [debug] Selected integrity[2] ciphering[0]
[2024-07-23 07:09:46.975] [ngap] [debug] Initial Context Setup Request received
[2024-07-23 07:09:46.976] [nas] [debug] Registration accept received
[2024-07-23 07:09:46.976] [nas] [info] UE switches to state [MM-REGISTERED/NORMAL-SERVICE]
[2024-07-23 07:09:46.976] [nas] [debug] Sending Registration Complete
[2024-07-23 07:09:46.976] [nas] [info] Initial Registration is successful
[2024-07-23 07:09:46.976] [nas] [debug] Sending PDU Session Establishment Request
[2024-07-23 07:09:46.976] [nas] [debug] UAC access attempt is allowed for identity[0], category[MO_sig]
[2024-07-23 07:09:47.182] [nas] [debug] Configuration Update Command received
[2024-07-23 07:09:47.206] [ngap] [info] PDU session resource(s) setup for UE[1] count[1]
[2024-07-23 07:09:47.206] [nas] [debug] PDU Session Establishment Accept received
[2024-07-23 07:09:47.207] [nas] [info] PDU Session establishment is successful PSI[1]
[2024-07-23 07:09:47.239] [app] [info] Connection setup for PDU session[1] is successful, TUN interface[uesimtun0, 10.45.0.2] is up.
```

The appliance comes with a preinstalled [UERANSIM](https://github.com/aligungr/UERANSIM) software, and includes the following features:

* Pre-configured UE sample equipement
* Basic 5G network configuration parameters

:warning: This appliance is meant to be used together with a 5G core, not part of this appliance.

## Contextualization
Contextualization parameters provided in the Virtual Machine template controls the initial VM configuration. Except for the common set of parameters supported by every appliance on the OpenNebula Marketplace, there are few specific to the particular UERANSIM appliance.

The parameters should be provided in the CONTEXT section of the Virtual Machine template, read the [OpenNebula Management and Operations Guide](https://docs.opennebula.io/stable/management_and_operations) for more details.

| Parameter                      | Description                                                         |
|--------------------------------|---------------------------------------------------------------------|
| ONEAPP_UERAN_NETWORK_MCC       | Mobile Country Code value                                           |
| ONEAPP_UERAN_NETWORK_MNC       | Mobile Network Code value (2 or 3 digits)                           |
| ONEAPP_UERAN_CELL_ID           | NR Cell Identity (36-bit)                                           |
| ONEAPP_UERAN_GNB_ID            | NR gNB ID length in bits [22...32]                                  |
| ONEAPP_UERAN_TAC_ID            | Tracking Area Code                                                  |
| ONEAPP_UERAN_AMF_IP            | AMF IP Address                                                      |
| ONEAPP_UERAN_AMF_PORT          | AMF_PORT                                                            |
| ONEAPP_UERAN_SST_ID            | List of supported S-NSSAIs by this gNB slices                       |
| ONEAPP_UERAN_UE_IMSI           | IMSI number of the UE. IMSI = [MCC\|MNC\|MSISDN] (total 15 digits)  |
| ONEAPP_UERAN_SUBSCRIPTION_KEY  | Permanent subscription key                                          |
| ONEAPP_UERAN_OPERATOR_CODE     | Operator code (OP or OPC) of the UE                                 |
| ONEAPP_UERAN_VNF_IP            | IP of the virtual router to connect to the OneKE cluster            |
| ONEAPP_UERAN_CORE_SUBNET       | Subnet assigned to the 5G core services                             |

## Known Issues and Limitation

Certain settings, like static route configuration are not persistent at UERANSIM appliance. Thus, in case of appliance reboot it might be necessary to reconfigure it persistently.
