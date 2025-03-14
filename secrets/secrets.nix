let
  authorizedKeys = [
    # altair.dolphin-emu.org
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGI7y3Nvirnxwi0RCWYpl15nRCq352lnAH4IqgY5Es8w"
    # deneb.dolphin-emu.org
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL27x43hRYoi8x5EFHvCLFdNHENGlcr2iod3J1liLdBg"
    # degasus
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBfpcFMGpTNUUdmeMgNurPgj+mi2VBjFOcCQ3FcpDaO0"
    # MayImilae
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAibDWW0pesc3G7BGleBOVJbZpJIw1/CfB/SbBSsuo8l"
    # OatmealDome
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICAu/HTxWWR6vrEP2IgKy+sG9OT9B8/C+PE4d2U6b/Zz"
    # JosJuice
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF+Q3PYfm5B/lLtRQBo7OR2Jdjv9TwBSJaOp8MrBB4uF"
  ];

  allFiles = [
    "alerts-smtp-password.age"
    "android-keystore.age"
    "android-keystore-pass.age"
    "androidpublisher-service-key.age"
    "backup-passphrase.age"
    "backup-ssh-key.age"
    "backup-ssh-known-hosts.age"
    "buildbot-change-hook-credentials.age"
    "buildbot-downloads-create-key.age"
    "buildbot-flat-manager-worker-token.age"
    "buildbot-gh-client-id.age"
    "buildbot-gh-client-secret.age"
    "buildbot-steam-username.age"
    "buildbot-steam-password.age"
    "buildbot-workers-passwords.age"
    "central-change-hook-username.age"
    "central-change-hook-password.age"
    "central-discord-token.age"
    "container-builder-env.age"
    "discord-bot-env.age"
    "etherpad-apikey.age"
    "etherpad-sessionkey.age"
    "etherpad-passwords.age"
    "fifoci-frontend-api-key.age"
    "fifoci-frontend-secret-key.age"
    "flat-manager-repo-key.age"
    "flat-manager-secret.age"
    "flatpak-worker-env-altair.age"
    "flatpak-worker-env-deneb.age"
    "geoip-license-key.age"
    "gh-app-priv-key.age"
    "gh-hook-hmac.age"
    "grafana-admin-password.age"
    "grafana-secret-key.age"
    "infra-smtp-relay.age"
    "mastodon-smtp-password.age"
    "nas-credentials-flatpak.age"
    "nas-credentials.age"
    "oci-registry-htpasswd.age"
    "oci-registry-password.age"
    "update-signing-key.age"
    "wiki-bot-password.age"
  ];
in
  builtins.listToAttrs (builtins.map
    (fn: { name = fn; value.publicKeys = authorizedKeys; })
    allFiles
  )
