# Changelog

## 1.0.0-20260924

First version of the CernVM-FS Proxy appliance.

- Squid from Ubuntu 24.04 LTS, configured as a CernVM-FS site proxy on port 3128.
- The EESSI repositories, the repositories of CERN and the Open Science Grid, and the servers
  of the configuration repository `cvmfs-config.cern.ch` are allowed by default. Other domains
  are added in the wizard.
- Only the subnet of the first NIC may use the proxy by default. Other networks are added in
  the wizard.
- Disk and memory cache sizes in the wizard, and an optional second disk for the cache, which
  the proxy finds by itself.
- The VM publishes `CVMFS_PROXY_URL` and `READY=YES` to OneGate once a CernVM-FS file of
  EESSI downloads through the proxy, and the reason in `ERROR` when a check fails.
