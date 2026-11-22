# Spike findings — 2026-11-17 (Galaxy S24 Ultra SM-S928B, Android 17)

Plan: `plans/2026-11-17-plan1-s24-spike.md`. Card: NTAG213, UID `04DB8FE23B1590`, still holding the
original `https://www.wtechkw.com` URI record during these checks.

| # | Check | Result | Notes |
|---|---|---|---|
| A | UID read with app open, browser suppressed | **Pass** | `CARD 04DB8FE23B1590 via reader mode (app open) \| tech=NfcA/MifareUltralight/Ndef ndef=[wellKnown:U]`; the app stayed in front, no browser |
| B | GPS on tap (accuracy, fix time, mocked flag) | **Pass** | 29.341204, 48.009902; ±19.5–33.9 m; first fix 1410 ms, then 41–89 ms; `mocked=false` |
| C | GPS indoors vs window/outdoors | Partial | Indoors only (±19.5–33.9 m); window/outdoor not measured |
| D | Write MIME + AAR records | Not run | User moved on to the full build |
| E | Records read back | Not run | |
| F | App closed → one tap opens app AND delivers UID | Not run | Full app implements it; verify in the end-to-end test |
| G | App in background → tap delivers UID | Not run | Same |
| H | NFC Tools sanity check | Not run | |

## Observations
- **Holding the card produces a new read about every second** (11:57:52, :53, :54, :55). The 10 s
  same-UID debounce in spec §6.2 is required, otherwise one long tap punches in and then out.
- Indoor accuracy of 20–34 m is well inside the default 100 m radius plus the 50 m accuracy allowance.

## Decisions for Plan 3
- One-tap punch from a closed app: implemented, verification moved to the end-to-end test.
- GPS budget (§6.2: reuse a fix ≤ 30 s old, wait ≤ 10 s): keep.
- Writing the MIME + AAR records needs our app (NFC Tools cannot write the custom MIME record), so
  the full app gets Settings → **Prepare wall card** (Android only, with confirmation).
