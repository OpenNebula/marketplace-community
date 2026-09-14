# Changelog

## 1.0.0-20260914

First release.

- One image for the three roles of the service, selected with `ONEAPP_ROLE`.
- Open OnDemand 4.2 on Ubuntu 24.04, with its own LDAP directory and Dex authentication.
- Shared home over NFS, exported with `root_squash` to the workers and without it to the
  portal only, the role that creates each home on first login.
- Scientific software from EESSI 2025.06 over CernVM-FS, through a site cache on the
  storage role.
- Five interactive applications: JupyterLab, Octave, a C++ notebook, RStudio and VS Code.
- Elastic pool of compute VMs. Every worker reports its session count to OneGate, OneFlow
  resizes the role, and the portal sends each new session to the least loaded worker.
- A worker created from the image reaches `READY` in well under a minute.
- The image ships no directory and no password. The portal creates its LDAP directory at
  first boot with an administrator password it generates and keeps in
  `/etc/one-ondemand/ldap-admin.pass`, readable by root only.
- `ONEAPP_OOD_SSL_MODE` accepts `custom`, with the certificate chain and the private key
  given in `ONEAPP_OOD_SSL_CERT` and `ONEAPP_OOD_SSL_KEY`.
- Each role names its VM after itself, `ood-portal`, `ood-storage` and `ood-worker-<octet>`.
