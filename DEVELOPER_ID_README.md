You need an Apple Developer ID cert pair, not App Store certs.

  1. Create a CSR on the Mac that will sign releases.

  open /Applications/Utilities/Keychain\ Access.app

  - Keychain Access -> Certificate Assistant -> Request a Certificate from a Certificate Authority...
  - Fill email + common name, leave CA email empty, choose Saved to disk.

  2. Create cert(s) in Apple Developer portal.

  - Go to: https://developer.apple.com/account/resources/certificates/list
  - + -> under Software choose:
      - Developer ID Application (required for app + DMG signing)
      - Developer ID Installer (only needed if you ship .pkg)
  - Upload the .certSigningRequest, download .cer.

  3. Install cert(s).

  - Double-click each downloaded .cer.
  - In Keychain Access, confirm under My Certificates that each cert has a private key beneath it.

  4. Verify in terminal.

  security find-identity -v -p codesigning | rg "Developer ID Application|Developer ID Installer"

  5. Update your script identity to the exact cert string found above.

  - Scripts/sign-and-notarize.sh:6
  - Example format:
      - Developer ID Application: Your Name (TEAMID)

  6. Re-run:

  ./Scripts/sign-and-notarize.sh

  Notes:

  - Apple Distribution certs do not replace Developer ID Application for outside-App-Store notarized DMG distribution.
  - Creating Developer ID certs requires Account Holder (or cloud-managed Developer ID permissions as configured by Apple roles).

  Sources:

  - https://developer.apple.com/help/account/certificates/create-developer-id-certificates/
  - https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request
  - https://developer.apple.com/developer-id/

