# Building the appliance image

Copy these files to `apps-code/community-apps/packer/open-ondemand/` in the
[marketplace-community](https://github.com/OpenNebula/marketplace-community) repository, and
add the name `open-ondemand` to the `SERVICES :=` line of
`apps-code/community-apps/Makefile.config`. Without that change, `make open-ondemand` is not a
valid target, so the pull request reviewer cannot build the image.

Nothing else is needed, because `appliance.sh` is self-contained like the one in every
published appliance and carries the logic of the three roles inside it.
`marketplace/build-appliance-sh.sh` composes it from the project repository, so it is not
edited by hand.

    make open-ondemand

The image is written to `apps-code/community-apps/export/open-ondemand.qcow2`.

## Why this image is bigger than average

The image carries the software of the three roles: Open OnDemand with its Dex and its LDAP
directory, the NFS server and the site Squid, and Apptainer with the session SIF image and
code-server. One image for the three roles is one thing to build, publish and document, and
the OneKS appliance is packaged the same way.

The scientific catalogue does **not** go inside the image. It comes from EESSI over
CernVM-FS at boot, the way EESSI is meant to be used, so the image does not age as the
software changes.
