# Connect IQ Store listing

Upload at https://apps.garmin.com/developer/upload

- Beta: upload `bin/widget-beta.iq` and `bin/watchface-beta.iq` with **Beta App** checked.
  Only your account can see and install them.
- Release: upload `bin/widget.iq` and `bin/watchface.iq` (production app IDs), Beta unchecked.
- Store icon (500x500): `assets/store/icon-500.png`
- Hero image (1440x720): `assets/store/hero.png`
- Screen images (500x500, under 150 KB each):
  - Widget: `screen-1-widget`, `screen-3-high`, `screen-4-low`, `screen-5-glance`, `screen-6-signal-loss`, `screen-8-widget-mip`
  - Watch face: `screen-2-watchface`, `screen-7-watchface-mip` (plus `screen-1-widget` to show the pair)

Regenerate after design changes: `scripts/shots.sh` (or just the shots you need, e.g.
`scripts/shots.sh face-venu3`), then `python3 scripts/gen_store_images.py`.

---

## Trendline (widget)

**Category:** Health & Fitness

**Description:**

Your CGM glucose on your wrist: the current value, trend arrow, change since the last reading, and a smooth 3-hour trend graph colored by range.

Works with Dexcom G6 and G7 through Dexcom Share (the same service Dexcom Follow uses). No extra app on your phone: sign in with your Dexcom account in the app settings.

FEATURES
- Large value with trend arrow (all 7 Dexcom directions) and the change since the previous reading
- Countdown to the next reading; turns red when a reading is overdue
- 3-hour graph with a smooth line that shifts color with your glucose, guide lines at your low and high thresholds, and labeled peaks and troughs
- Clear states for LOW, HIGH, signal loss, sensor errors and connection problems
- mg/dL or mmol/L, with your own low and high thresholds
- Glance on supported watches, refreshed in the background
- Smart refresh: checks for data right after each new reading should arrive and learns your typical upload delay, so it's fresh without wasting battery

SETUP
1. In the Dexcom app on your phone, make sure Share is turned on.
2. Install Trendline, then open its settings in the Connect IQ app.
3. Enter your Dexcom username and password and choose your region.

Pair with the Trendline Face watch face to see your glucose on your watch face.

Not affiliated with or endorsed by Dexcom, Inc. Dexcom, Dexcom G6, Dexcom G7 and Dexcom Share are trademarks of Dexcom, Inc.

IMPORTANT: Trendline is for informational purposes only. It is not a medical device and is not intended for diagnosis, treatment or dosing decisions. Readings can be delayed or missing. Always confirm with your CGM receiver or phone app before acting.

PRIVACY: Your Dexcom login is stored in the app's settings on your watch and phone. Because Garmin watches cannot parse Dexcom's login response format directly, the app sends your login over HTTPS to a small proxy that forwards it to Dexcom and returns readings. The proxy does not store credentials or readings.

**Note for reviewers:** enter `demo` as the username (no password) to see synthetic data. In demo mode, tap the screen to cycle through LOW, HIGH, signal loss, sensor error and no-data states.

---

## Trendline Face (watch face)

**Category:** Watch Faces

**Description:**

A clean watch face built around your CGM: time with seconds, date, battery, your current glucose with trend arrow, change and time since the reading, and six configurable data fields.

Works with Dexcom G6 and G7 through Dexcom Share. Sign in with your Dexcom account in the watch face settings.

FEATURES
- Glucose value, trend arrow, change and time since the reading, colored by your thresholds
- Time since the reading turns red when a reading is overdue; clear signal loss and sensor error states
- Six data fields (two left, two right, two bottom), each with an icon: steps, heart rate, distance, elevation, next sunrise/sunset, temperature, calories, floors, active minutes
- Battery with charging indicator and a Do Not Disturb moon
- Smart background refresh timed to each new reading
- Low-power friendly, with a minimal always-on mode on AMOLED watches

On watches without built-in weather, temperature comes from Open-Meteo using your last known location (shared only with Open-Meteo). Sunrise/sunset and temperature need a location: on some watches that's only after a GPS activity.

Not affiliated with or endorsed by Dexcom, Inc. Dexcom, Dexcom G6, Dexcom G7 and Dexcom Share are trademarks of Dexcom, Inc.

IMPORTANT: For informational purposes only. Not a medical device; not for diagnosis, treatment or dosing decisions. Readings can be delayed or missing.

PRIVACY: Your Dexcom login is sent over HTTPS to a small proxy that forwards it to Dexcom (Garmin watches cannot parse Dexcom's login response directly). The proxy does not store credentials or readings. If you use the temperature field on a watch without built-in weather, your approximate location (rounded to about 1 km) is sent to Open-Meteo.

**Note for reviewers:** enter `demo` as the username (no password) to see synthetic data.
