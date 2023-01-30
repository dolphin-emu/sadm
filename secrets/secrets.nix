let
  authorizedKeys = [
    # altair.dolphin-emu.org
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGI7y3Nvirnxwi0RCWYpl15nRCq352lnAH4IqgY5Es8w"
    # delroth
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII3tjB4KYDok3KlWxdBp/yEmqhhmybd+w0VO4xUwLKKV"
  ];

  allFiles = [
    "androidpublisher-service-key.age"
    "backup-passphrase.age"
    "backup-ssh-key.age"
    "backup-ssh-known-hosts.age"
    "container-builder-env.age"
    "etherpad-apikey.age"
    "etherpad-sessionkey.age"
    "etherpad-passwords.age"
    "fifoci-frontend-api-key.age"
    "fifoci-frontend-secret-key.age"
    "geoip-license-key.age"
    "gh-bot-token.age"
    "gh-hook-hmac.age"
    "gh-oauth-client-id.age"
    "gh-oauth-client-secret.age"
    "grafana-admin-password.age"
    "grafana-secret-key.age"
    "infra-smtp-relay.age"
    "mastodon-smtp-password.age"
    "nas-credentials.age"
    "oci-registry-htpasswd.age"
    "oci-registry-password.age"
    "wiki-bot-password.age"
  ];
in
  builtins.listToAttrs (builtins.map
    (fn: { name = fn; value.publicKeys = authorizedKeys; })
    allFiles
  )
