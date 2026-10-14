# Hardware test results

Phones are referred to by model and OS version only (no serial numbers or IMEIs).
Test IDs refer to `tools/HARDWARE_CHECKLIST.md` (numbers) and to the session plan
(S = smoke, A = Android core, B = Android extra, C = iOS).

| Test ID | Date | Test phone | Peripheral | Build type | Result | Evidence | Notes |
|---|---|---|---|---|---|---|---|
| S1 Smoke test | 2026-10-14 | Phone A Galaxy A53 5G, Android 16 | Phone B Galaxy S20 5G (Android 13) via nRF Connect | debug | PASS | manual screenshots | Connected; notifications enabled (CCCD written by plugin); sent 01,02,03,06 as uint32 LE; app showed counter 6, received 4, missed 2, "gap: missed 2" event. |

## Failures

None recorded yet.

## Setup limitations

None recorded yet.
