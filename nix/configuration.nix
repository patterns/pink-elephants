{ config, pkgs, lib, ... }:

let
  user = "fermyon";
  hostname = "bartholomew";
in {

  boot = {
    kernelPackages = pkgs.linuxKernel.packages.linux_rpi4;
    initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" ];
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };
  };
####  swapDevices = [ {
####    device = "/var/lib/swapfile";
####    size = 16*1024;
####  } ];
  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "${pkgs.terminus_font}/share/consolefonts/ter-132n.psf.gz";
    packages = with pkgs; [ terminus_font ];
    keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  };

  networking = {
    hostName = hostname;
  };

  environment.systemPackages = with pkgs; [
    vim
    tailscale
    fermyon-spin
    cloudflared
    abduco
    dvtm
  ];

  services.openssh.enable = true;
  services.tailscale.enable = true;

  users = {
    mutableUsers = true;
    users."${user}" = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        # CHANGE HERE
        "ssh-rsa "
      ];
    };
  };

  hardware.enableRedistributableFirmware = true;
  system.stateVersion = "23.11";
}

