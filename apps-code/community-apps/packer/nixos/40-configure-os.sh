#!/usr/bin/env bash

exec 1>&2
set -eux -o pipefail

nixos-generate-config --root /mnt/ --no-filesystems

install -d /mnt/etc/nixos/configuration.nix.d/

cat >/mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, lib, ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      cloud-init = prev.cloud-init.overrideAttrs (old: {
        prePatch = ''
          substituteInPlace cloudinit/sources/DataSourceOpenNebula.py \\
            --replace '["sudo", "-u", user]' '["\${pkgs.sudo}/bin/sudo", "-u", user]'
        '' + old.prePatch;
      });
    })
  ];

  environment.systemPackages = with pkgs; [
    bash bat
    cdrkit
    fd file
    git
    htop
    iproute2
    jq
    mc
    nftables
    ripgrep
    sudo
    tcpdump tmux
    unzip
    vim
    zip
  ];

  imports = [ ./hardware-configuration.nix ] ++ (lib.pipe ./configuration.nix.d [
    builtins.readDir
    (lib.filterAttrs (name: _: lib.hasSuffix ".nix" name))
    (lib.mapAttrsToList (name: _: ./configuration.nix.d + "/\${name}"))
  ]);

  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  swapDevices = [ ];

  boot.loader.grub.enable  = true;
  boot.loader.grub.device  = "/dev/vda";
  boot.kernelParams        = [ "net.ifnames=0" "biosdevname=0" ];
  boot.kernelModules       = [ "kvm-amd" "kvm-intel" ];
  boot.growPartition       = true;

  networking.useDHCP         = false;
  networking.useNetworkd     = true;
  networking.firewall.enable = false;

  time.timeZone = "UTC";

  i18n.defaultLocale = "en_US.UTF-8";

  security.sudo.wheelNeedsPassword = false;

  users.users.nixos = {
    isNormalUser = true;
    extraGroups  = [ "wheel" ];
  };

  services.openssh.enable = true;

  services.cloud-init.enable         = true;
  services.cloud-init.network.enable = true;
  services.cloud-init.settings       = { datasource_list = [ "OpenNebula" "NoCloud" ]; };

  system.stateVersion = "$(nixos-version | cut -d. -f-2)";
}
EOF

sync
