import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// Sunrise/sunset from the standard almanac algorithm (accurate to ~1-2 min).
module Sun {
    const ZENITH = 90.833;

    // Returns [utcSeconds, isSunrise] for the next sunrise or sunset, or null
    // during polar day/night.
    function next(lat as Float, lon as Float, now as Number) as Array? {
        var today = Time.today().value();
        var offset = System.getClockTime().timeZoneOffset;
        for (var day = 0; day < 3; day++) {
            var dayStart = today + day * 86400;
            // Calendar date of this local day, expressed as its UTC midnight.
            var utcMidnight = dayStart + offset;
            var n = (utcMidnight / 86400) - (yearStartDays(utcMidnight)) + 1;
            var rise = calc(n, lat, lon, true);
            var set = calc(n, lat, lon, false);
            if (rise != null) {
                var r = place(utcMidnight + (rise * 3600).toNumber(), dayStart);
                if (r > now) {
                    return [r, true];
                }
            }
            if (set != null) {
                var s = place(utcMidnight + (set * 3600).toNumber(), dayStart);
                if (s > now) {
                    return [s, false];
                }
            }
        }
        return null;
    }

    // Days since the epoch at Jan 1 of the year containing utcSecs.
    function yearStartDays(utcSecs as Number) as Number {
        var days = utcSecs / 86400;
        var year = 1970;
        var d = 0;
        while (true) {
            var len = isLeap(year) ? 366 : 365;
            if (d + len > days) {
                return d;
            }
            d += len;
            year++;
        }
        return d;
    }

    function isLeap(y as Number) as Boolean {
        return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    }

    function place(t as Number, dayStart as Number) as Number {
        while (t < dayStart) {
            t += 86400;
        }
        while (t >= dayStart + 86400) {
            t -= 86400;
        }
        return t;
    }

    // UTC hour of sunrise/sunset on day-of-year n, or null if it doesn't occur.
    function calc(n as Number, lat as Float, lon as Float, rising as Boolean) as Float? {
        var lngHour = lon / 15.0;
        var t = n + ((rising ? 6.0 : 18.0) - lngHour) / 24.0;
        var m = 0.9856 * t - 3.289;
        var l = norm(m + 1.916 * sinD(m) + 0.020 * sinD(2 * m) + 282.634, 360.0);
        var ra = norm(Math.atan(0.91764 * Math.tan(rad(l))) * 180.0 / Math.PI, 360.0);
        var lQuad = Math.floor(l / 90.0) * 90.0;
        var raQuad = Math.floor(ra / 90.0) * 90.0;
        ra = (ra + lQuad - raQuad) / 15.0;

        var sinDec = 0.39782 * sinD(l);
        var cosDec = Math.cos(Math.asin(sinDec));
        var cosH = (Math.cos(rad(ZENITH)) - sinDec * sinD(lat)) / (cosDec * Math.cos(rad(lat)));
        if (cosH > 1.0 || cosH < -1.0) {
            return null;
        }
        var hDeg = Math.acos(cosH) * 180.0 / Math.PI;
        var hr = (rising ? 360.0 - hDeg : hDeg) / 15.0;
        var localT = hr + ra - 0.06571 * t - 6.622;
        return norm(localT - lngHour, 24.0).toFloat();
    }

    function rad(d as Numeric) as Float {
        return (d * Math.PI / 180.0).toFloat();
    }

    function sinD(d as Numeric) as Float {
        return Math.sin(rad(d)).toFloat();
    }

    function norm(x as Numeric, range as Float) as Float {
        return (x - Math.floor(x / range) * range).toFloat();
    }
}
