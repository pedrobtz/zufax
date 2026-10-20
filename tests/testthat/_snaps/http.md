# http_get() refuses URLs off the allowlist before any request

    Code
      http_get("http://169.254.169.254/metadata/identity/oauth2/token")
    Condition
      Error:
      ! Refusing to request http://169.254.169.254/metadata/identity/oauth2/token: not on the zufax allowlist.

