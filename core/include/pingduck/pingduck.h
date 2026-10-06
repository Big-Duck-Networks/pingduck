/*
 * pingduck-core public C ABI.
 *
 * Everything exposed here is plain C (fixed-size structs, C callbacks) so it
 * can be bound directly from Dart FFI, used by the headless agent, and called
 * from the CLI without any language bridging.
 *
 * Threading: discovery functions block until finished. Device callbacks may be
 * invoked from a worker thread, but never concurrently for one call. From
 * Dart, use NativeCallable.listener.
 */
#ifndef PINGDUCK_H
#define PINGDUCK_H

#include <stdint.h>

#if defined(_WIN32)
#  if defined(PINGDUCK_BUILDING)
#    define PD_API __declspec(dllexport)
#  elif defined(PINGDUCK_SHARED)
#    define PD_API __declspec(dllimport)
#  else
#    define PD_API
#  endif
#else
#  define PD_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Return codes ------------------------------------------------------ */
#define PD_OK               0
#define PD_ERR_INVALID_ARG -1
#define PD_ERR_SOCKET      -2
#define PD_ERR_UNSUPPORTED -3   /* e.g. ARP sniffing without libpcap        */
#define PD_ERR_PERMISSION  -4   /* raw sockets / pcap need elevated rights  */
#define PD_ERR_NOT_FOUND   -5
#define PD_ERR_TIMEOUT     -6
#define PD_ERR_CANCELLED   -7

/* ---- Discovery source flags (pd_device.sources) ------------------------ */
#define PD_SRC_ICMP  (1u << 0)
#define PD_SRC_MDNS  (1u << 1)
#define PD_SRC_SSDP  (1u << 2)
#define PD_SRC_ARP   (1u << 3)  /* MAC from libpcap sniffing or OS ARP cache */
#define PD_SRC_DNS   (1u << 4)  /* hostname from reverse DNS                 */

/* ---- Sweep option flags ------------------------------------------------ */
#define PD_SWEEP_RESOLVE_DNS (1u << 0) /* reverse-DNS each live host          */
#define PD_SWEEP_ARP_CACHE   (1u << 1) /* read MAC from OS ARP cache if allowed */
#define PD_SWEEP_DEFAULT_CONCURRENCY 128

#define PD_IP_LEN        16
#define PD_MAC_LEN       18
#define PD_HOSTNAME_LEN  256
#define PD_VENDOR_LEN    128
#define PD_MODEL_LEN     128
#define PD_SERVICES_LEN  512

typedef struct pd_device {
    char     ip[PD_IP_LEN];             /* dotted quad                         */
    char     mac[PD_MAC_LEN];           /* "aa:bb:cc:dd:ee:ff" or ""           */
    char     hostname[PD_HOSTNAME_LEN]; /* best known name or ""               */
    char     vendor[PD_VENDOR_LEN];     /* OUI or UPnP manufacturer or ""      */
    char     model[PD_MODEL_LEN];       /* UPnP modelName / friendlyName or "" */
    char     services[PD_SERVICES_LEN]; /* comma-separated, e.g. "_airplay._tcp" */
    int32_t  rtt_ms;                    /* ICMP round trip, -1 if unknown      */
    uint32_t sources;                   /* PD_SRC_* bitmask                    */
} pd_device;

typedef struct pd_interface {
    char     name[64];         /* OS interface name / adapter friendly name */
    char     ip[PD_IP_LEN];
    char     netmask[PD_IP_LEN];
    char     broadcast[PD_IP_LEN];
    char     gateway[PD_IP_LEN];  /* "" if unknown */
    char     dns[PD_IP_LEN];      /* first IPv4 DNS server, "" if unknown */
    char     mac[PD_MAC_LEN];     /* "" if unknown */
    uint8_t  prefix_len;
} pd_interface;

/* Called once per discovered/updated device. `dev` is only valid during the call. */
typedef void (*pd_device_cb)(const pd_device* dev, void* user);

/* For bindings whose callbacks run asynchronously (Dart NativeCallable.listener):
 * pass pd_forward_copy as the `cb` of any discovery call and a
 * pd_device_owned_cb as its `user`. Each device then arrives as a heap copy
 * that the receiver releases with pd_device_free(). */
typedef void (*pd_device_owned_cb)(pd_device* dev);
PD_API void pd_forward_copy(const pd_device* dev, void* owned_cb);
PD_API void pd_device_free(pd_device* dev);

/* ---- Lifecycle --------------------------------------------------------- */
PD_API const char* pd_version(void);
PD_API int  pd_init(void);       /* safe to call more than once */
PD_API void pd_shutdown(void);
PD_API const char* pd_strerror(int code);

/* Request that running discovery calls return early with PD_ERR_CANCELLED. */
PD_API void pd_cancel(void);

/* ---- Interfaces -------------------------------------------------------- */
/* Picks the interface that most likely is "the LAN": has a default gateway,
 * otherwise the first private, non-loopback, non-link-local IPv4. */
PD_API int pd_default_interface(pd_interface* out);
/* Fills up to `max` interfaces; returns the count written or a negative error. */
PD_API int pd_list_interfaces(pd_interface* out, int max);

/* Gateway and DNS server learned by the host app, for platforms that hide
 * them from native code (Android 10+ blocks /proc/net/route). They fill the
 * gaps of the interface whose subnet contains them; values the OS reports
 * win. Either may be NULL or "" to clear it. */
PD_API int pd_set_lan_hints(const char* gateway, const char* dns);

/* ---- Active discovery -------------------------------------------------- */
/* Ping a single host. Returns RTT in ms (>= 0) or a negative error. */
PD_API int pd_ping(const char* ip, int timeout_ms);

/* Concurrent ICMP sweep of a CIDR (e.g. "192.168.1.0/24"; max /16).
 * Invokes `cb` as soon as each host responds. With PD_SWEEP_RESOLVE_DNS, hosts
 * that resolve are reported a second time (same ip) with the hostname filled in,
 * so treat callbacks as upserts (the same applies to MACs found late). Returns
 * the number of live hosts. */
PD_API int pd_sweep(const char* cidr, int timeout_ms, int concurrency,
                    uint32_t flags, pd_device_cb cb, void* user);

/* mDNS / DNS-SD discovery (Bonjour/Zeroconf). Returns number of devices. */
PD_API int pd_mdns_discover(int timeout_ms, pd_device_cb cb, void* user);

/* SSDP M-SEARCH + UPnP device description XML. Returns number of devices. */
PD_API int pd_ssdp_discover(int timeout_ms, pd_device_cb cb, void* user);

/* Raw ARP sweep via libpcap (agent mode, needs root/CAP_NET_RAW).
 * `iface` may be NULL for the default interface; `cidr` may be NULL for its subnet.
 * Returns PD_ERR_UNSUPPORTED when built without libpcap. */
PD_API int pd_arp_scan(const char* iface, const char* cidr, int timeout_ms,
                       pd_device_cb cb, void* user);

/* Look up an IP in the OS neighbour/ARP cache. Not available on iOS 14+/Android 10+. */
PD_API int pd_arp_cache_lookup(const char* ip, char* mac_out /* PD_MAC_LEN */);

/* Reverse lookup: PTR via the LAN DNS server, unicast mDNS and NetBIOS,
 * capped at ~1.5s. Returns PD_OK and fills `out`, or PD_ERR_NOT_FOUND. */
PD_API int pd_reverse_dns(const char* ip, char* out, int out_len);

/* ---- Combined scan ---------------------------------------------------- */
#define PD_SCAN_ICMP      (1u << 0)
#define PD_SCAN_MDNS      (1u << 1)
#define PD_SCAN_SSDP      (1u << 2)
#define PD_SCAN_ARP       (1u << 3)  /* libpcap; silently skipped if unsupported */
#define PD_SCAN_DNS       (1u << 4)  /* reverse DNS for ICMP hits               */
#define PD_SCAN_ARP_CACHE (1u << 5)  /* OS ARP cache for ICMP hits              */
#define PD_SCAN_DEFAULT   (PD_SCAN_ICMP | PD_SCAN_MDNS | PD_SCAN_SSDP | PD_SCAN_DNS | PD_SCAN_ARP_CACHE)

/* Runs the selected discovery methods in parallel and merges results by IP.
 * `cb` fires whenever a device is first seen *or* gains new information, each
 * time with the full merged record, so UIs can simply upsert by ip.
 * `cidr` may be NULL to scan the default interface's subnet.
 * Returns the number of distinct devices. */
PD_API int pd_scan(const char* cidr, int timeout_ms, uint32_t flags, pd_device_cb cb, void* user);

/* ---- Diagnostics ------------------------------------------------------- */
/* TCP connect scan. `open_out[i]` is set to 1 if ports[i] accepted. Returns open count. */
PD_API int pd_port_scan(const char* ip, const uint16_t* ports, int count,
                        int timeout_ms, uint8_t* open_out);

/* Send a Wake-on-LAN magic packet. `broadcast` may be NULL for 255.255.255.255. */
PD_API int pd_wake_on_lan(const char* mac, const char* broadcast);

/* ---- OUI vendor lookup ------------------------------------------------- */
/* Load the IEEE MA-L registry CSV (https://standards-oui.ieee.org/oui/oui.csv).
 * Returns the number of entries loaded. */
PD_API int pd_oui_load(const char* csv_path);
/* Same as pd_oui_load, from CSV text in memory (e.g. a bundled app asset). */
PD_API int pd_oui_load_buffer(const char* csv, int64_t len);
/* Returns PD_OK and fills `out` with the vendor name, or PD_ERR_NOT_FOUND. */
PD_API int pd_oui_lookup(const char* mac, char* out, int out_len);

#ifdef __cplusplus
}
#endif

#endif /* PINGDUCK_H */
