# Changelog

## 1.0.0-20260916

Redesign of the service inputs, 16 September 2026. The instantiate wizard showed four tabs
named after variable fragments, the only required field in "others", the OpenID Connect
provider split across two tabs and two empty PEM boxes for everyone.

- No required input. `ONEAPP_POOL_RANGE` leaves the wizard. The portal derives the worker
  range from its compute interface, the whole /24 around its address, and the variable
  stays as an advanced context attribute for a standalone portal or a compute network
  larger than a /24.
- A check that stops a role at boot is published through OneGate as the `ERROR` attribute
  of the VM, so Sunstone shows it on the VM and `onevm show` lists it, without opening a
  console. A switch turned on with its field empty is the usual case.
- `ONEAPP_AUTH_LOCAL_USERS` is validated before the directory is seeded. A duplicate user
  name or uid, a missing password, a uid under 1000 or a name with capitals stops the portal
  with a message that names the entry.
- Four tabs, Portal, Users and login, Home directories and Slurm, each with a title, and
  every optional feature in its own section behind an `_ENABLED` switch,
  so an unused feature shows one switch and nothing else. The names follow the tabs.
  `ONEAPP_PORTAL_HOST_NAME` replaces `ONEAPP_OOD_SERVERNAME`. `ONEAPP_AUTH_LOCAL_USERS`
  replaces `ONEAPP_LDAP_USERS`. `ONEAPP_AUTH_OIDC_ENABLED` with `ONEAPP_AUTH_OIDC_ISSUER`,
  `ONEAPP_AUTH_OIDC_CLIENT_ID`, `ONEAPP_AUTH_OIDC_CLIENT_SECRET` and `ONEAPP_AUTH_OIDC_NAME`
  replace `ONEAPP_OIDC_ISSUER`, `ONEAPP_OIDC_CLIENT_ID`, `ONEAPP_OIDC_CLIENT_SECRET` and
  `ONEAPP_OIDC_NAME`. `ONEAPP_HOME_NFS_ENABLED` with `ONEAPP_HOME_NFS_SERVER` and
  `ONEAPP_HOME_NFS_EXPORT` replace `ONEAPP_NFS_SERVER` and `ONEAPP_NFS_EXPORT`.
  `ONEAPP_SLURM_CONTROLLER_ENABLED` with `ONEAPP_SLURM_CONTROLLER_HOST` replace
  `ONEAPP_SLURM_CONTROLLER`.
- The certificate list is gone. The default is a self-signed certificate,
  `ONEAPP_PORTAL_LETSENCRYPT_ENABLED` requests one from Let's Encrypt, and
  `ONEAPP_PORTAL_CERTIFICATE_ENABLED` installs the chain and the key given in
  `ONEAPP_PORTAL_CERTIFICATE_CHAIN` and `ONEAPP_PORTAL_CERTIFICATE_KEY`. They replace
  `ONEAPP_OOD_SSL_MODE`, `ONEAPP_OOD_SSL_CERT` and `ONEAPP_OOD_SSL_KEY`.
- Worker tuning leaves the wizard. `ONEAPP_WORKER_IDLE_SECONDS` and
  `ONEAPP_WORKER_MAX_SESSIONS` keep their names and defaults as advanced context
  attributes, set in the `vm_template_contents` of a role.
- No backward compatibility with the previous names. The appliance is unreleased, and this
  entry is the record of the rename.

## 1.0.0-20260915

First release.

- One image for the three roles of the service, selected with `ONEAPP_ROLE`.
- The portal takes its list of workers from OneGate, so a VM that is not part of the service never receives a session; the address range is only probed on a standalone portal.
- Open OnDemand 4.2 on Ubuntu 24.04, with its own LDAP directory and Dex authentication.
- Shared home over NFS, exported with `root_squash` to the workers and without it to the
  portal only, the role that creates each home on first login.
- Scientific software from EESSI 2025.06 over CernVM-FS, through a site cache on the
  storage role.
- Six interactive applications: JupyterLab, Octave, a C++ notebook, RStudio, VS Code and an
  Xfce desktop in the browser (TurboVNC on the VM, noVNC on the portal).
- Elastic pool of compute VMs. Every worker reports its session count to OneGate, OneFlow
  resizes the role, and the portal sends each new session to the least loaded worker.
- A worker created from the image reaches `READY` in well under a minute.
- The image ships no directory and no password. The portal creates its LDAP directory at
  first boot with an administrator password it generates and keeps in
  `/etc/one-ondemand/ldap-admin.pass`, readable by root only.
- `ONEAPP_OOD_SSL_MODE` accepts `custom`, with the certificate chain and the private key
  given in `ONEAPP_OOD_SSL_CERT` and `ONEAPP_OOD_SSL_KEY`.
- Each role names its VM after itself, `ood-portal`, `ood-storage` and `ood-worker-<octet>`.
- A second disk on the storage role keeps the homes across services, and
  `ONEAPP_NFS_SERVER` points the roles at an NFS server the site already runs.
- The pool shrinks one worker at a time, when the oldest worker has been empty for
  `ONEAPP_WORKER_IDLE_SECONDS`. New sessions go to the youngest of the least loaded workers,
  so the oldest one drains.
- `ONEAPP_WORKER_MAX_SESSIONS` caps the sessions a worker takes, the pool grows when every
  worker is at the cap, and each worker publishes `SESSION_USERS`, who has a session and
  since when.
- An OpenID Connect provider on the login page, through Dex, with `ONEAPP_OIDC_*`. Verified
  end to end against a Dex provider on 15 September 2026.
- GPU workers prepared: a wrapper adds `--nv` to the session container on a VM with an
  NVIDIA device, and the README shows the role with PCI passthrough. Untested, no GPU at hand.
- Worker sizes. Any `worker_<size>` role in the service template is a second pool, and the
  application forms offer the sizes that exist.
- The OpenID Connect connector no longer requires the preferred_username claim: it falls
  back to the email, so providers that omit the claim work. Verified against a Dex provider.
- The portal publishes its address as `OOD_URL` in the attributes of its VM, next to `READY`.
- The VM template lists only the service inputs as user inputs. The values the service
  derives per role are not, so the Sunstone instantiate wizard has no "Roles Inputs" step
  that could send them back empty and override the role expressions.
- A Slurm cluster as a second target. `ONEAPP_SLURM_CONTROLLER`, as a service input or
  added later with `onevm updateconf`, declares the controller of a OneSlurm service that
  shares the users and the home, and the Job Composer and Active Jobs offer it beside the
  VM pool through an SSH proxy, with no Slurm client on the portal.
- Prometheus metrics of the whole service on the portal, port 9101, and a `HEALTHY`
  attribute per worker that keeps new sessions away from a worker missing its home, its
  software catalogue or sshd.
- No fixed addresses. The storage role asks OneGate which VM plays the portal and grants
  root on the home export to that address alone, and takes the compute network from its
  own NIC, so the service asks only for the address range of the compute network.
