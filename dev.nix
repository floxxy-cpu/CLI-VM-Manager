{ pkgs, ... }: {
  # Which nixpkgs channel to use.
  channel = "stable-24.05"; # or "unstable"
  
  # Use https://search.nixos.org/packages to find packages
  packages = [
    pkgs.unzip
    pkgs.openssh
    pkgs.git
    pkgs.cpuid
    pkgs.qemu_kvm
    pkgs.sudo
    pkgs.cdrkit
    pkgs.cloud-utils
    pkgs.qemu
    pkgs.libvirt
    pkgs.virt-manager
    pkgs.virt-viewer
    pkgs.htop
    pkgs.btop
    pkgs.iotop
    pkgs.nethogs
    pkgs.curl
    pkgs.wget
    pkgs.screen
    pkgs.tmux
    pkgs.bc
    pkgs.neofetch
    pkgs.python3
    pkgs.nodejs
    pkgs.jdk
    pkgs.openssl
    pkgs.mkpasswd
    pkgs.rustc
    pkgs.cargo
    pkgs.docker
    pkgs.docker-compose
  ];
  
  # Sets environment variables in the workspace
  env = {};
  
  idx = {
    # Search for the extensions you want on https://open-vsx.org/ and use "publisher.id"
    extensions = [
      "Dart-Code.flutter"
      "Dart-Code.dart-code"
      "ms-python.python"
      "ms-vscode.vscode-typescript-next"
      "ms-azuretools.vscode-azure"
      "ms-kubernetes-tools.vscode-kubernetes-tools"
    ];

    workspace = {
      # Runs when a workspace is first created with this `dev.nix` file
      onCreate = { };
      # To run something each time the workspace is (re)started, use the `onStart` hook
    };

    # Disable previews completely
    previews = {
      enable = false;
    };
  };
}
