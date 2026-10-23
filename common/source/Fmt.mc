import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Display formatting and the glucose color scale.
(:glance)
module Fmt {
    var low as Number = 70;
    var high as Number = 180;
    var mmol as Boolean = false;

    // Color stops as [mg/dL, color] pairs, rebuilt when settings change.
    var _stops as Array<Number> = [];

    const LATE_SECS = 5 * 60;      // a new reading was due
    const STALE_SECS = 15 * 60;    // value greyed out
    const EXPIRED_SECS = 60 * 60;  // value hidden
    // Set in load(): softer on AMOLED, full-chroma on MIP.
    var LATE_COLOR as Number = 0xFF5555;

    function load() as Void {
        low = prop("low", 70);
        high = prop("high", 180);
        if (high <= low + 20) {
            high = low + 20;
        }
        mmol = Application.Properties.getValue("units") == 1;

        var urgentLow = low - 15 < 40 ? 40 : low - 15;
        var justLow = low > urgentLow ? low - 1 : low;
        var justHigh = high + 1;
        // Flat lime across the in-range band. MIP uses the 64-color primaries
        // (00/55/AA/FF) so reflective screens stay vivid; AMOLED keeps softer tones.
        if (isMip()) {
            LATE_COLOR = 0xFF0000;
            _stops = [
                urgentLow, 0xFF0000,
                justLow,   0xFF5500,
                low,       0x00FF00,
                high,      0x00FF00,
                justHigh,  0xFFFF00,
                high + 70, 0xFFAA00,
                high + 140, 0xFF5500
            ];
        } else {
            LATE_COLOR = 0xFF5555;
            _stops = [
                urgentLow, 0xBB2222,
                justLow,   0xFF5A5A,
                low,       0x55EE66,
                high,      0x55EE66,
                justHigh,  0xFFEE00,
                high + 70, 0xFF9900,
                high + 140, 0xFF6600
            ];
        }
    }

    function prop(key as String, def as Number) as Number {
        var v = Application.Properties.getValue(key);
        return (v instanceof Number && v > 0) ? v : def;
    }

    // Smoothly blends between the stops so each value gets its own shade.
    function color(v as Number) as Number {
        if (_stops.size() == 0) {
            load();
        }
        var n = _stops.size();
        if (v <= _stops[0]) {
            return _stops[1];
        }
        for (var i = 2; i < n; i += 2) {
            var hiV = _stops[i];
            if (v <= hiV) {
                var loV = _stops[i - 2];
                if (hiV <= loV) {
                    return _stops[i + 1];
                }
                return blend(_stops[i - 1], _stops[i + 1], (v - loV).toFloat() / (hiV - loV));
            }
        }
        return _stops[n - 1];
    }

    function blend(a as Number, b as Number, f as Float) as Number {
        var r = mix((a >> 16) & 0xFF, (b >> 16) & 0xFF, f);
        var g = mix((a >> 8) & 0xFF, (b >> 8) & 0xFF, f);
        var bl = mix(a & 0xFF, b & 0xFF, f);
        return (r << 16) | (g << 8) | bl;
    }

    function mix(a as Number, b as Number, f as Float) as Number {
        return (a + (b - a) * f + 0.5).toNumber();
    }

    // No API for palette size; AMOLED/LCD advertise burn-in or getDisplayMode.
    function isMip() as Boolean {
        var ds = System.getDeviceSettings();
        if ((ds has :requiresBurnInProtection) && ds.requiresBurnInProtection) {
            return false;
        }
        if (System has :getDisplayMode) {
            return false;
        }
        return true;
    }

    // Dexcom Share values: 39 = LOW, 401 = HIGH, below 39 = sensor error code.
    function isNumeric(v as Number) as Boolean {
        return v >= 40 && v <= 400;
    }

    function isSensorError(v as Number) as Boolean {
        return v < 39;
    }

    function isWord(v as Number) as Boolean {
        return v == 39 || v > 400;
    }

    function value(v as Number) as String {
        if (v < 39) {
            return "---";
        }
        if (v < 40) {
            return "LOW";
        }
        if (v > 400) {
            return "HIGH";
        }
        if (mmol) {
            return (v * 0.0555).format("%.1f");
        }
        return v.format("%d");
    }

    function delta(d as Number?) as String {
        if (d == null) {
            return "";
        }
        var sign = d < 0 ? "-" : "+";
        var a = d < 0 ? -d : d;
        if (mmol) {
            return sign + (a * 0.0555).format("%.1f");
        }
        return sign + a.format("%d");
    }

    function age(secs as Number) as String {
        if (secs < 60) {
            return "now";
        }
        if (secs < 3600) {
            return (secs / 60).format("%d") + "m";
        }
        if (secs < 86400) {
            return (secs / 3600).format("%d") + "h";
        }
        return ">1d";
    }

    // Time since the last reading: "3:07", or "1h 05m" past an hour.
    function elapsed(secs as Number) as String {
        if (secs < 0) {
            secs = 0;
        }
        if (secs < 3600) {
            return (secs / 60).format("%d") + ":" + (secs % 60).format("%02d");
        }
        if (secs < 86400) {
            return (secs / 3600).format("%d") + "h " + ((secs % 3600) / 60).format("%02d") + "m";
        }
        return ">1 day";
    }

    function countdown(secs as Number) as String {
        if (secs < 0) {
            secs = 0;
        }
        return (secs / 60).format("%d") + ":" + (secs % 60).format("%02d");
    }

    function units() as String {
        return mmol ? "mmol/L" : "mg/dL";
    }
}

(:glance)
module Draw {
    // Trend codes (Dexcom order): 1 DoubleUp, 2 SingleUp, 3 FortyFiveUp, 4 Flat,
    // 5 FortyFiveDown, 6 SingleDown, 7 DoubleDown. Others have no arrow.
    function hasArrow(code as Number) as Boolean {
        return code >= 1 && code <= 7;
    }

    function arrowWidth(size as Number, code as Number) as Number {
        if (!hasArrow(code)) {
            return 0;
        }
        return (code == 1 || code == 7) ? (size * 1.5).toNumber() : size;
    }

    // Draws the arrow centered at (cx, cy) in the current color.
    function arrow(dc as Graphics.Dc, cx as Number, cy as Number, size as Number, code as Number) as Void {
        var deg;
        if (code == 1 || code == 2) {
            deg = -90;
        } else if (code == 3) {
            deg = -45;
        } else if (code == 4) {
            deg = 0;
        } else if (code == 5) {
            deg = 45;
        } else if (code == 6 || code == 7) {
            deg = 90;
        } else {
            return;
        }
        var aa = dc has :setAntiAlias;
        if (aa) {
            dc.setAntiAlias(true);
        }
        if (code == 1 || code == 7) {
            var off = (size * 0.38).toNumber();
            single(dc, cx - off, cy, size * 0.85, deg);
            single(dc, cx + off, cy, size * 0.85, deg);
        } else {
            single(dc, cx, cy, size, deg);
        }
        if (aa) {
            dc.setAntiAlias(false);
        }
    }

    function single(dc as Graphics.Dc, cx as Number, cy as Number, size as Numeric, deg as Number) as Void {
        var shape = [-0.5, -0.15, 0.0, -0.15, 0.0, -0.46, 0.5, 0.0, 0.0, 0.46, 0.0, 0.15, -0.5, 0.15];
        var a = deg * Math.PI / 180.0;
        var c = Math.cos(a);
        var s = Math.sin(a);
        var pts = new [7];
        for (var i = 0; i < 7; i++) {
            var x = shape[i * 2] * size;
            var y = shape[i * 2 + 1] * size;
            pts[i] = [(cx + x * c - y * s + 0.5).toNumber(), (cy + x * s + y * c + 0.5).toNumber()];
        }
        dc.fillPolygon(pts);
    }
}
