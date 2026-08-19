# Roadmap

This is a local utility, not a research program.

## Known residual

Official Grok may still overwrite `auth.json` if it persists
in-memory tokens on a path that never re-reads disk. Sibling lock
covers grok 1.0.5 refresh / lock-timeout / sibling-rotation paths.

## Next (only if the user asks)

- Install/restart the LaunchAgent on a machine that already has
  `grok login`
- Further lock-protocol tightening against official Grok updates
