import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// The data shown in the six configurable slots: a value plus a drawn icon.
module Fields {
    enum {
        NONE = 0,
        STEPS = 1,
        HEART = 2,
        DISTANCE = 3,
        ELEVATION = 4,
        SUN = 5,
        TEMPERATURE = 6,
        CALORIES = 7,
        FLOORS = 8,
        ACTIVE_MIN = 9
    }

    var _sun as Array? = null;
    var _sunCheckedAt as Number = 0;

    // Demo mode (username starting with "demo") shows sample activity data so
    // the face looks complete in the simulator, screenshots and store review.
    var demo as Boolean = false;
    const DEMO_TEXT = ["", "8432", "64", "3.6mi", "820ft", "6:24", "61\u00b0", "1840", "12", "145"];

    function text(id as Number, now as Number) as String {
        if (demo && id > NONE && id < DEMO_TEXT.size()) {
            return DEMO_TEXT[id];
        }
        if (id == STEPS) {
            var steps = ActivityMonitor.getInfo().steps;
            if (steps == null) {
                return "--";
            }
            return steps >= 10000 ? (steps / 1000.0).format("%.1f") + "k" : steps.format("%d");
        } else if (id == HEART) {
            return heartRate();
        } else if (id == DISTANCE) {
            var cm = ActivityMonitor.getInfo().distance;
            if (cm == null) {
                return "--";
            }
            if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
                return (cm / 160934.4).format("%.1f") + "mi";
            }
            return (cm / 100000.0).format("%.1f") + "km";
        } else if (id == ELEVATION) {
            return elevation();
        } else if (id == SUN) {
            var ev = sunEvent(now);
            return ev == null ? "--" : clock(ev[0] as Number);
        } else if (id == TEMPERATURE) {
            return temperature(now);
        } else if (id == CALORIES) {
            var cal = ActivityMonitor.getInfo().calories;
            return cal == null ? "--" : cal.format("%d");
        } else if (id == FLOORS) {
            var info = ActivityMonitor.getInfo();
            if (info has :floorsClimbed && info.floorsClimbed != null) {
                return info.floorsClimbed.format("%d");
            }
            return "--";
        } else if (id == ACTIVE_MIN) {
            var info = ActivityMonitor.getInfo();
            if (info has :activeMinutesWeek && info.activeMinutesWeek != null) {
                return info.activeMinutesWeek.total.format("%d");
            }
            return "--";
        }
        return "";
    }

    function heartRate() as String {
        var hr = null;
        var act = Activity.getActivityInfo();
        if (act != null) {
            hr = act.currentHeartRate;
        }
        if (hr == null && ActivityMonitor has :getHeartRateHistory) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                hr = sample.heartRate;
            }
        }
        return hr == null ? "--" : (hr as Number).format("%d");
    }

    function elevation() as String {
        var meters = null;
        var act = Activity.getActivityInfo();
        if (act != null && act.altitude != null) {
            meters = act.altitude;
        }
        if (meters == null && Toybox has :SensorHistory && Toybox.SensorHistory has :getElevationHistory) {
            var sample = Toybox.SensorHistory.getElevationHistory({ :period => 1 }).next();
            if (sample != null && sample.data != null) {
                meters = sample.data;
            }
        }
        if (meters == null) {
            return "--";
        }
        if (System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE) {
            return (meters * 3.28084).format("%d") + "ft";
        }
        return meters.format("%d") + "m";
    }

    // Prefer Garmin weather; fall back to the Open-Meteo value the background
    // service cached (also used when Weather exists but hasn't synced yet).
    function temperature(now as Number) as String {
        var c = null;
        if (Toybox has :Weather) {
            var cond = Toybox.Weather.getCurrentConditions();
            if (cond != null && cond.temperature != null) {
                c = cond.temperature;
            }
        }
        if (c == null) {
            var at = Application.Storage.getValue("wxAt");
            var wx = Application.Storage.getValue("wx");
            if (at instanceof Number && now - at < 3 * 3600 && wx != null) {
                c = wx;
            }
        }
        if (c == null) {
            return "--";
        }
        var ds = System.getDeviceSettings();
        if ((ds has :temperatureUnits) && ds.temperatureUnits == System.UNIT_STATUTE) {
            return (c * 1.8 + 32).format("%d") + "\u00b0";
        }
        return (c as Numeric).format("%d") + "\u00b0";
    }

    // Next sunrise or sunset as [utcSeconds, isSunrise], refreshed hourly.
    function sunEvent(now as Number) as Array? {
        if (_sun != null && (_sun[0] as Number) > now && now - _sunCheckedAt < 3600) {
            return _sun;
        }
        _sunCheckedAt = now;
        var loc = location();
        _sun = loc == null ? null
            : Sun.next((loc[0] as Numeric).toFloat(), (loc[1] as Numeric).toFloat(), now);
        return _sun;
    }

    // Last known position, remembered across restarts. Watch faces can't start
    // GPS; they only see a location after a GPS activity, a weather sync, or
    // (on some devices) the last Position fix.
    function location() as Array? {
        var deg = null;
        var act = Activity.getActivityInfo();
        if (act != null && act.currentLocation != null) {
            deg = act.currentLocation.toDegrees();
        }
        if (deg == null && Toybox has :Weather) {
            var cond = Toybox.Weather.getCurrentConditions();
            if (cond != null && cond.observationLocationPosition != null) {
                deg = cond.observationLocationPosition.toDegrees();
            }
        }
        if (deg == null && Toybox has :Position) {
            var info = Position.getInfo();
            if (info != null && info.position != null) {
                deg = info.position.toDegrees();
            }
        }
        if (deg != null && validLocation(deg)) {
            var loc = [deg[0].toFloat(), deg[1].toFloat()];
            Application.Storage.setValue("loc", loc);
            return loc;
        }
        var saved = Application.Storage.getValue("loc");
        return saved instanceof Array ? saved : null;
    }

    function validLocation(deg as Array) as Boolean {
        if (deg[0] == null || deg[1] == null) {
            return false;
        }
        var la = deg[0].toFloat();
        var lo = deg[1].toFloat();
        // 180/180 is the CIQ "no fix" sentinel some devices return from Position.
        return la >= -90.0 && la <= 90.0 && lo >= -180.0 && lo <= 180.0
            && !(la == 0.0 && lo == 0.0)
            && !(la == 180.0 && lo == 180.0);
    }

    function clock(utc as Number) as String {
        var info = Gregorian.info(new Time.Moment(utc), Time.FORMAT_SHORT);
        var hour = info.hour as Number;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return hour.format("%d") + ":" + (info.min as Number).format("%02d");
    }

    // Icon glyphs in the generated Icons font (Material Symbols, see gen_fonts.py).
    const GLYPHS = ["", "a", "b", "c", "d", "e", "g", "h", "i", "j"];
    const COLORS = [0, 0x55AAFF, 0xFF5555, 0x55FF55, 0xAAAAAA, 0xFFAA00, 0xFFAA55, 0xFF5500, 0xAAAAFF, 0xFFFF55];
    // Full-chroma 64-color MIP primaries (same slots as COLORS).
    const COLORS_MIP = [0, 0x00FFFF, 0xFF0000, 0x00FF00, 0xAAAAAA, 0xFFAA00, 0xFFAA00, 0xFF5500, 0xAA55FF, 0xFFFF00];

    // Draws the icon for a field centered at (cx, cy).
    function icon(dc as Graphics.Dc, font as Graphics.FontType, id as Number, cx as Number, cy as Number,
                  now as Number) as Void {
        if (id <= NONE || id >= GLYPHS.size()) {
            return;
        }
        var glyph = GLYPHS[id];
        if (id == SUN) {
            var ev = sunEvent(now);
            glyph = demo || (ev != null && !(ev[1] as Boolean)) ? "f" : "e";
        }
        var palette = Fmt.isMip() ? COLORS_MIP : COLORS;
        dc.setColor(palette[id], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, font, glyph, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Fetch Open-Meteo whenever temperature is shown. Garmin weather is tried
    // first at display time; this covers watches with no Weather API and ones
    // where weather simply hasn't synced yet.
    function needsWeatherFetch(slots as Array<Number>) as Boolean {
        return slots.indexOf(TEMPERATURE) >= 0;
    }
}
