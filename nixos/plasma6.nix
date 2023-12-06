self: {
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  kdePackages = self.packages.${pkgs.stdenv.system};
  xcfg = config.services.xserver;
  cfg = xcfg.desktopManager.plasma6;

  inherit (lib) literalExpression mkDefault mkIf mkOption mkPackageOptionMD types;
in {
  options = {
    services.xserver.desktopManager.plasma6 = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc "Enable the Plasma 6 (KDE 6) desktop environment.";
      };

      notoPackage = mkPackageOptionMD pkgs "Noto fonts" {
        default = ["noto-fonts"];
        example = "noto-fonts-lgc-plus";
      };
    };

    environment.plasma6.excludePackages = mkOption {
      description = lib.mdDoc "List of default packages to exclude from the configuration";
      type = types.listOf types.package;
      default = [];
      example = literalExpression "[ pkgs.plasma5Packages.oxygen ]";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.enable -> !config.services.xserver.desktopManager.plasma5.enable;
        message = "Cannot enable plasma5 and plasma6 at the same time!";
      }
    ];

    qt.enable = true;
    environment.systemPackages = with kdePackages; let
      requiredPackages = [
        # Hack? To make everything run on Wayland
        qtwayland

        # Frameworks with globally loadable bits
        frameworkintegration # provides Qt plugin
        kauth # provides helper service
        kcoreaddons # provides extra mime type info
        kded # provides helper service
        kfilemetadata # provides Qt plugins
        kguiaddons # provides geo URL handlers
        kiconthemes # provides Qt plugins
        kimageformats # provides Qt plugins
        kio # provides helper service + a bunch of other stuff
        kpackage # provides kpackagetool tool
        kservice # provides kbuildsycoca6 tool
        kwallet # provides helper service
        kwallet-pam # provides helper service
        kwalletmanager # provides KCMs and stuff
        plasma-activities # provides plasma-activities-cli tool
        solid # provides solid-hardware6 tool

        # Core Plasma parts
        kwin
        pkgs.xwayland

        kscreen
        libkscreen

        kscreenlocker

        kactivitymanagerd
        kde-cli-tools
        kwrited # wall message proxy, not to be confused with kwrite

        milou
        polkit-kde-agent-1

        plasma-desktop
        plasma-workspace

        # Crash handler
        drkonqi

        # Application integration
        libplasma # provides Kirigami platform theme
        plasma-integration # provides Qt platform theme
        pkgs.plasma5Packages.kwayland-integration # provides Qt5 Wayland integration
        kde-gtk-config

        # Artwork + themes
        breeze
        breeze-icons
        breeze-gtk
        ocean-sound-theme
        plasma-workspace-wallpapers
        pkgs.hicolor-icon-theme # fallback icons

        # misc Plasma extras
        kdeplasma-addons

        pkgs.xdg-user-dirs # recommended upstream
        xdg-desktop-portal-kde # FIXME: figure out how to install this properly

        # Plasma utilities
        kmenuedit

        kinfocenter
        plasma-systemmonitor
        ksystemstats
        libksysguard

        spectacle
        systemsettings

        # Gear
        dolphin
        dolphin-plugins
        ffmpegthumbs
        kdegraphics-thumbnailers
        kde-inotify-survey
        kio-admin
        kio-extras

        # HACK: required by sddm, consider rewrapping sddm
        qtvirtualkeyboard

        # FIXME: not an overlay because too many rebuilds
        (lib.hiPrio (pkgs.xdg-utils.overrideAttrs (old: {
          patches =
            old.patches
            or []
            ++ [
              # Add KDE6 support
              (pkgs.fetchpatch {
                url = "https://gitlab.freedesktop.org/xdg/xdg-utils/-/merge_requests/67.diff";
                hash = "sha256-DRepY4zZ+AYgEti9qm0gizWoXZZnObcweM5pKLNATh0=";
              })
            ];
        })))
      ];
      optionalPackages = [
        plasma-browser-integration
        konsole
        (lib.getBin qttools) # Expose qdbus in PATH

        ark
        elisa
        gwenview
        pkgs.plasma5Packages.okular
        khelpcenter
        print-manager
      ];
    in
      requiredPackages
      ++ utils.removePackagesByName optionalPackages config.environment.plasma6.excludePackages
      # Optional hardware support features
      ++ lib.optionals config.hardware.bluetooth.enable [bluedevil bluez-qt pkgs.openobex pkgs.obexftp]
      ++ lib.optional config.networking.networkmanager.enable plasma-nm
      ++ lib.optional config.hardware.pulseaudio.enable plasma-pa
      ++ lib.optional config.services.pipewire.pulse.enable plasma-pa
      ++ lib.optional config.powerManagement.enable powerdevil
      # FIXME: broken
      # ++ lib.optional config.services.colord.enable colord-kde
      ++ lib.optional config.services.hardware.bolt.enable plasma-thunderbolt
      ++ lib.optionals config.services.samba.enable [kdenetwork-filesharing pkgs.samba]
      ++ lib.optional config.services.xserver.wacom.enable wacomtablet
      ++ lib.optional config.services.flatpak.enable flatpak-kcm;

    environment.pathsToLink = [
      # FIXME: modules should link subdirs of `/share` rather than relying on this
      "/share"
    ];

    environment.etc."X11/xkb".source = xcfg.xkb.dir;

    # Needed for things that depend on other store.kde.org packages to install correctly,
    # notably Plasma look-and-feel packages (a.k.a. Global Themes)
    #
    # FIXME: this is annoyingly impure and should really be fixed at source level somehow,
    # but kpackage is a library so we can't just wrap the one thing invoking it and be done.
    # This also means things won't work for people not on Plasma, but at least this way it
    # works for SOME people.
    environment.sessionVariables.KPACKAGE_DEP_RESOLVERS_PATH = "${kdePackages.frameworkintegration.out}/libexec/kf6/kpackagehandlers";

    # Enable GTK applications to load SVG icons
    services.xserver.gdk-pixbuf.modulePackages = [pkgs.librsvg];

    fonts.packages = [cfg.notoPackage pkgs.hack-font];
    fonts.fontconfig.defaultFonts = {
      monospace = ["Hack" "Noto Sans Mono"];
      sansSerif = ["Noto Sans"];
      serif = ["Noto Serif"];
    };

    programs.ssh.askPassword = mkDefault "${kdePackages.ksshaskpass.out}/bin/ksshaskpass";

    # Enable helpful DBus services.
    services.accounts-daemon.enable = true;
    # when changing an account picture the accounts-daemon reads a temporary file containing the image which systemsettings5 may place under /tmp
    systemd.services.accounts-daemon.serviceConfig.PrivateTmp = false;

    services.power-profiles-daemon.enable = mkDefault true;
    services.system-config-printer.enable = mkIf config.services.printing.enable (mkDefault true);
    services.udisks2.enable = true;
    services.upower.enable = config.powerManagement.enable;
    services.xserver.libinput.enable = mkDefault true;

    # Extra UDEV rules used by Solid
    services.udev.packages = [
      # libmtp has "bin", "dev", "out" outputs. UDEV rules file is in "out".
      pkgs.libmtp.out
      pkgs.media-player-info
    ];

    # Set up Dr. Konqi as crash handler
    systemd.packages = [kdePackages.drkonqi];
    systemd.services."drkonqi-coredump-processor@".wantedBy = ["systemd-coredump@.service"];
    systemd.user.sockets."drkonqi-coredump-launcher".wantedBy = ["sockets.target"];

    xdg.portal.enable = true;
    xdg.portal.extraPortals = [kdePackages.xdg-desktop-portal-kde];
    xdg.portal.configPackages = mkDefault [kdePackages.xdg-desktop-portal-kde];
    services.pipewire.enable = mkDefault true;

    services.xserver.displayManager = {
      sessionPackages = [kdePackages.plasma-workspace];
      defaultSession = mkDefault "plasma";
    };
    services.xserver.displayManager.sddm.theme = mkDefault "breeze";

    security.pam.services = {
      login.enableKwallet = true;
      kde.enableKwallet = true;
      # FIXME: do these actually work? https://invent.kde.org/plasma/kscreenlocker/-/merge_requests/163
      kde-fingerprint.fprintAuth = true;
      kde-smartcard.p11Auth = true;
    };

    programs.dconf.enable = true;
    programs.firefox.nativeMessagingHosts.packages = [kdePackages.plasma-browser-integration];
    programs.kdeconnect.package = kdePackages.kdeconnect-kde;

    # FIXME: make this overrideable upstream, also this wrapper is very hacky
    nixpkgs.overlays = [
      (final: prev: {
        libsForQt5 = prev.libsForQt5.overrideScope (_: __: {
          sddm = kdePackages.sddm.overrideAttrs (old: {
            buildInputs = old.buildInputs ++ (with kdePackages; [kirigami qtsvg ksvg plasma5support qt5compat breeze-icons]);
          });
        });
      })
    ];
  };
}
