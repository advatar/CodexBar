1) Proper local signing (stable, fewer prompts, not distributable)

  - Create/import a local signing cert:
      - ./Scripts/setup_dev_signing.sh
  - Set identity in your shell:
      - export APP_IDENTITY='CodexBar Development'
  - Rebuild:
      - ./Scripts/compile_and_run.sh
  - Confirm it no longer says ad-hoc in Scripts/compile_and_run.sh:179.

  2) Proper public distribution signing (Developer ID + notarization)

  - Install Developer ID Application cert + private key in login keychain.
  - Verify it exists:
      - security find-identity -v -p codesigning | rg "Developer ID Application"
  - Ensure the identity string matches Scripts/sign-and-notarize.sh:6 (edit if your cert name differs).
  - Provide notarization/signing env vars (usually in .env, auto-loaded by Scripts/sign-and-notarize.sh):
      - APP_STORE_CONNECT_API_KEY_P8
      - APP_STORE_CONNECT_KEY_ID
      - APP_STORE_CONNECT_ISSUER_ID
      - SPARKLE_PRIVATE_KEY_FILE
  - Run release signing:
      - ./Scripts/sign-and-notarize.sh
  - Validate outputs:
      - codesign --verify --deep --strict --verbose TeamTokenBar.app
      - spctl -a -t exec -vv TeamTokenBar.app
      - xcrun stapler validate TeamTokenBar.app
      - spctl -a -t open -vv TeamTokenBar-<version>.dmg
