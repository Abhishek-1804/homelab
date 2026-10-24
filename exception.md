# Exceptions

Steps that aren't automated and have to be done by hand.

## Restoring a Hermes backup

After restoring a Hermes backup, always run the restore script; never just
`hermes import` on its own:

```bash
gh release download <tag> -R Abhishek-1804/hermes-backups
hack/hermes-restore.sh hermes-backup-<date>.zip
```

A backup can carry old copies of the secrets Kubernetes provides (from
1Password), and Hermes's own `.env` wins over the pod's environment. The script
imports the zip, removes those keys from Hermes's `.env`, turns off profile
multiplexing (which makes Hermes ignore the pod's environment) and restarts
Hermes, so 1Password's secrets are the ones in use.

Without a zip (`hack/hermes-restore.sh`), it does only the clean-up and restart:
run it whenever Discord or Claude stops working after a change in Hermes's
dashboard.
