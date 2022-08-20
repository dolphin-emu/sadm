let
  authorizedKeys = [
    # altair.dolphin-emu.org
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGI7y3Nvirnxwi0RCWYpl15nRCq352lnAH4IqgY5Es8w"
    # delroth
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII3tjB4KYDok3KlWxdBp/yEmqhhmybd+w0VO4xUwLKKV"
  ];
in {
  "geoip-license-key.age".publicKeys = authorizedKeys;
}
