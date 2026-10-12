# Running the PingDuck agent on Proxmox

The PingDuck agent is one Docker container. On Proxmox it needs two things the
defaults don't always give it:

- **A direct line onto the LAN.** The container uses the host's network
  (`--net=host`), and that host must sit on the same layer-2 network as the
  devices you want to watch. No NAT in between.
- **Raw sockets.** The agent sends ICMP and ARP itself (`NET_RAW`) and listens
  for mDNS and SSDP multicast. A firewall that drops this traffic makes the
  agent see almost nothing, and makes the app unable to find the agent.

This guide covers a **VM (recommended)** and an **LXC container**, the network
filters that most often get in the way, and how to check it all works.

---

## 1. Pick a host

| | VM with Docker | LXC with Docker |
| --- | --- | --- |
| Setup | A small Debian or Ubuntu VM | A container with nesting turned on |
| Resources | ~512 MB RAM, 1 vCPU, 4 GB disk | Less |
| Raw sockets and multicast | Just works | Usually works; depends on the container's settings |
| Tested by us | Yes (KVM VM bridged onto the LAN) | No |

Use a VM unless you already run Docker in LXC and know its quirks.

---

## 2. VM setup (recommended)

1. **Create the VM.** Debian 12 or Ubuntu 22.04/24.04, 64-bit. In
   **Hardware → Network Device**:
   - **Bridge:** the bridge your LAN is on, usually `vmbr0`. Not an internal or
     NAT bridge.
   - **VLAN tag:** empty, unless the network you want to watch is a tagged VLAN.
     In that case, set its tag here.
   - **Firewall:** see [section 4](#4-network-filters-the-usual-problem) before
     turning this on.
2. **Give it an address on the LAN** (DHCP is fine). From inside the VM,
   `ip -4 addr` should show an address in the same subnet as your phone.
3. **Install Docker:**
   ```sh
   curl -fsSL https://get.docker.com | sh
   ```
4. **Run the agent:**
   ```sh
   docker run -d --name pingduck-agent --restart unless-stopped \
     --net=host --cap-add=NET_RAW --cap-add=NET_ADMIN \
     -v pingduck:/var/lib/pingduck \
     ghcr.io/big-duck-networks/pingduck-agent:latest
   ```
   Or with Compose (the same file as `agent/compose.yaml`):
   ```yaml
   services:
     pingduck-agent:
       image: ghcr.io/big-duck-networks/pingduck-agent:latest
       network_mode: host
       cap_add: [NET_RAW, NET_ADMIN]
       volumes: [pingduck:/var/lib/pingduck]
       restart: unless-stopped
   volumes:
     pingduck:
   ```
   The `pingduck` volume keeps the pairing across restarts and upgrades. Don't
   drop it.
5. **Pair it.** In the app, go to **Account › Add monitoring unit › Linux or
   Proxmox › Find my agent**. The phone must be on the same network.

---

## 3. LXC setup

Untested by us; these are the settings Docker needs inside LXC.

1. Create a Debian 12 container on the LAN bridge (`vmbr0`), the same as for
   a VM.
2. In **Options → Features**, turn on **nesting** (and **keyctl** for an
   unprivileged container). Docker doesn't run inside LXC without nesting.
3. Install Docker and run the agent exactly as in steps 3–4 above.
4. Check the sweep (section 5). If the agent finds the gateway but few other
   devices, or logs errors opening sockets, try a **privileged** container
   (uncheck *Unprivileged container* when creating it), or use a VM.

A privileged container runs with real root on the Proxmox host. That's a
security trade-off: the agent doesn't need it in a VM.

---

## 4. Network filters (the usual problem)

Filters between the agent and the LAN fail silently. The container runs, the
logs look normal, and the agent sees a fraction of the network, or the app
says **No agent found**. We hit this on our own test VM: the hypervisor
attached a MAC/IP filter to the VM's network card, and the phone's discovery
traffic never reached the VM.

What the agent needs to get through:

| Traffic | Direction | Why |
| --- | --- | --- |
| ARP and ICMP to every LAN address | out, and the replies in | The sweep |
| UDP 5353 (mDNS) and UDP 1900 (SSDP) multicast | both | Device names, and the app finding the agent |
| TCP 44480 | in, from the phone | Pairing (`/pingduck/v1/info`, `/pingduck/v1/pair`) |

**Proxmox firewall.** If **Firewall** is ticked on the VM's network device
*and* the firewall is enabled at Datacenter and VM level, the VM's default
input policy drops the phone's traffic. Either:
- untick **Firewall** on the agent VM's network device (simplest), or
- in **VM → Firewall**, add rules accepting **TCP 44480** and **UDP 1900, 5353**
  from your LAN subnet, and check **Options → Input Policy**.

Also in **VM → Firewall → Options**: leave **IP filter** off. **MAC filter** is
fine, since the agent never sends with another MAC.

**libvirt / other KVM managers.** Filters such as `clean-traffic`
(`<filterref filter='clean-traffic'/>` in the VM's interface XML) drop
traffic the hypervisor doesn't expect. Remove the filter from the agent VM's
interface, or use a plain bridge without it.

**How to tell a filter is in the way.** Inside the VM, while the phone runs
**Find my agent**:
```sh
sudo tcpdump -ni any 'udp port 1900 or tcp port 44480'
```
- **Packets from the phone's IP:** the network path is fine; look at the
  agent's logs instead.
- **Nothing at all:** something between the phone and the VM drops it, i.e. a
  filter, a different VLAN, or Wi-Fi client isolation on the access point.

A quick check from any other computer on the LAN:
```sh
curl http://<vm-ip>:44480/pingduck/v1/info
```
It should return JSON with `"app":"pingduck-agent"`.

---

## 5. Check it works

**Logs.** `docker logs pingduck-agent` should show, in order:
```
pingduck-agent 0.3.1 "<hostname>" (instance …), waiting to be added in the app
vendors: … OUI entries from /usr/share/pingduck/oui.csv
monitor: scanning the LAN every 300 s while paired
```
and after pairing:
```
pair: paired as agent …
monitor: 22 devices (21 with a MAC) synced; 22 new, 0 went offline
```
Lines to watch for:
- `ssdp: cannot use port 1900 or join the multicast group`: the container
  isn't on `--net=host`, or something else on the host holds port 1900.
- `http: cannot listen on port 44480`: another service holds the port. Set
  `-e PINGDUCK_HTTP_PORT=<port>`, or pair with a code (section 6).
- `monitor: the account's plan has no monitoring`: the account is on Free.

**Health.** `docker inspect --format '{{.State.Health.Status}}' pingduck-agent`
prints `healthy` once the agent answers.

**The sweep itself.** The image includes the scanner's command-line tool. Its
count should be close to what your router lists:
```sh
docker run --rm --net=host --cap-add=NET_RAW \
  --entrypoint pingduck ghcr.io/big-duck-networks/pingduck-agent:latest scan --arp
```
If ICMP finds devices but ARP finds almost none, a filter is dropping ARP
(section 4).

**The app.** **Account › Homelab Agent** shows the agent **Online**, and the
device list fills in with MACs and vendors after the first scan (about a
minute after pairing, then every 5 minutes).

---

## 6. VLANs, VPNs and other subnets

- **The phone can't reach the agent's network** (a separate VLAN, or you're
  setting it up remotely): in the app, choose **Pair with a code** on the
  No agent found screen, and start the container with the code:
  ```sh
  docker run -d --name pingduck-agent --restart unless-stopped \
    --net=host --cap-add=NET_RAW --cap-add=NET_ADMIN \
    -v pingduck:/var/lib/pingduck -e PINGDUCK_PAIRING_CODE=<code> \
    ghcr.io/big-duck-networks/pingduck-agent:latest
  ```
  The code is good for 10 minutes and used once.
- **Watch a different subnet than the host's own:** add
  `-e PINGDUCK_SCAN_CIDR=10.0.20.0/24`. ARP only works on a network the host is
  directly attached to; across a router the agent falls back to ICMP and
  gets no MACs. For a VLAN, give the VM a network device on that VLAN
  instead.
- **Scan more or less often:** `-e PINGDUCK_SCAN_INTERVAL=<seconds>` (60 s to
  24 h; default 300).

---

## 7. Upgrades and removal

```sh
docker pull ghcr.io/big-duck-networks/pingduck-agent:latest
docker rm -f pingduck-agent
# then the same docker run command as before
```
The `pingduck` volume keeps the pairing. To remove the agent completely,
revoke it in the app (**Homelab Agent › Revoke**), then
`docker rm -f pingduck-agent && docker volume rm pingduck`.
