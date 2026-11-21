# TAJIR Android release signing

The repository is public. **Never commit the release keystore or its password to the repository.** The Android APK must be signed with the same private key for every update so users can install new versions over existing versions.

## One-time GitHub Actions setup

1. Download and securely keep the TAJIR release keystore supplied to the project owner as `tajir-release-keystore.jks`.
2. Base64-encode the keystore:
   - Linux: `base64 -w0 tajir-release-keystore.jks`
   - macOS: `base64 -i tajir-release-keystore.jks | tr -d '\n'`
   - PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("tajir-release-keystore.jks"))`
3. Open the GitHub repository **Settings → Secrets and variables → Actions → New repository secret** and create these four secrets:

| Secret name | Value |
|---|---|
| `TAJIR_KEYSTORE_BASE64` | The complete base64 output from step 2 |
| `TAJIR_KEYSTORE_PASSWORD` | The keystore password supplied separately to the project owner |
| `TAJIR_KEY_ALIAS` | `tajir_release` |
| `TAJIR_KEY_PASSWORD` | The same password as `TAJIR_KEYSTORE_PASSWORD` |

4. Keep at least one encrypted/offline backup of the JKS file and password. If this key is lost, Android will not allow an update to replace an installation signed with it.

## Build behaviour

- Pull-request builds are compile checks only and upload an **unsigned CI artifact**. They do not publish a GitHub release.
- Builds on `main` require all four signing secrets, sign with Android `apksigner`, verify the signature, and only then upload/publish a signed APK.
- The in-app updater only offers APK assets whose filenames contain `signed`. It ignores old unsigned release assets.
- Do not distribute unsigned CI artifacts to users.
