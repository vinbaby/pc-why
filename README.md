# PC WHY?

**Windows problems without the Googling.**

PC WHY? is an early Windows diagnostic utility focused on one simple workflow:

**Diagnose → Explain → Fix → Verify**

Instead of claiming to fix hundreds of vague PC problems, PC WHY? aims to diagnose a small set of common Windows failures reliably, explain the evidence in plain language, perform only an appropriate low-risk repair, and verify that the original problem is actually gone.

## MVP targets

1. No Internet
2. No Sound
3. PC running unusually slow
4. Windows Update failed
5. C: drive full

The first working diagnostic module is **No Internet**.

## Product rules

- Diagnostic-first, repair-second.
- Never invent a problem when evidence is insufficient.
- Never report `Fixed` until the original diagnostic passes again.
- No registry cleaner.
- No automatic driver replacement.
- No hidden cleanup or unrelated system changes.
- Explain exactly what a proposed fix will change before applying it.
- Prefer Windows-native diagnostics and low-risk repairs.

## No Internet diagnostic tree

The first prototype checks, in order:

`Network adapter → IP configuration → Default gateway → Internet reachability → DNS resolution`

This helps distinguish a disabled/disconnected adapter, invalid IP configuration, gateway/local-network failure, upstream connectivity failure, and DNS failure instead of treating every network problem as the same issue.

## Status

**Prototype / research stage. Not ready for end-user installation.**

Current milestone: build and validate the first end-to-end **No Internet** module, including post-fix verification.

## Planned next step

Create a small Windows-native prototype that collects diagnostic evidence without modifying the machine. Repair actions will be added only after each diagnostic path can be tested safely.
