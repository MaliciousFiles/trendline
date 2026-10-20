import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//            [battery]
//             MON 19
//   L1       12:34 56       R1
//   L2             (moon)   R2
//         142 ↗ +4 3m
//        B1           B2
class GlucoseFaceView extends WatchUi.WatchFace {
    private const DIM = 0xAAAAAA;
    private const FAINT = 0x555555;
    private const SLOT_KEYS = ["slotL1", "slotL2", "slotR1", "slotR2", "slotB1", "slotB2"];
    private const SLOT_DEFAULTS = [Fields.DISTANCE, Fields.ELEVATION, Fields.SUN, Fields.TEMPERATURE,
                                   Fields.STEPS, Fields.HEART];

    private var _g as Glucose;
    private var _sleeping as Boolean = false;
    private var _burnIn as Boolean = false;
    private var _slots as Array<Number> = [0, 0, 0, 0, 0, 0];
    private var _partialOk as Boolean = true;

    private var _clock as Graphics.FontType = Graphics.FONT_NUMBER_MEDIUM;
    private var _sec as Graphics.FontType = Graphics.FONT_TINY;
    private var _line as Graphics.FontType = Graphics.FONT_SMALL;
    private var _label as Graphics.FontType = Graphics.FONT_XTINY;
    private var _icons as Graphics.FontType = Graphics.FONT_XTINY;

    // Where the seconds are drawn, for low-power partial updates: [x, y, w, h].
    private var _secBox as Array<Number> = [0, 0, 0, 0];

    function initialize() {
        WatchFace.initialize();
        _g = new Glucose();
        var ds = System.getDeviceSettings();
        _burnIn = (ds has :requiresBurnInProtection) && ds.requiresBurnInProtection;
        settingsChanged();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _clock = WatchUi.loadResource(Rez.Fonts.Clock) as Graphics.FontType;
        _sec = WatchUi.loadResource(Rez.Fonts.Sec) as Graphics.FontType;
        _line = WatchUi.loadResource(Rez.Fonts.Line) as Graphics.FontType;
        _label = WatchUi.loadResource(Rez.Fonts.Label) as Graphics.FontType;
        _icons = WatchUi.loadResource(Rez.Fonts.Icons) as Graphics.FontType;
    }

    function dataChanged() as Void {
        _g.reload();
    }

    function settingsChanged() as Void {
        for (var i = 0; i < SLOT_KEYS.size(); i++) {
            var v = Application.Properties.getValue(SLOT_KEYS[i]);
            _slots[i] = v instanceof Number ? v : SLOT_DEFAULTS[i];
        }
        Application.Storage.setValue("wxWant", Fields.needsWeatherFetch(_slots));
        var user = Application.Properties.getValue("username");
        Fields.demo = user instanceof String && user.find("demo") == 0;
        _g.reload();
    }

    function onEnterSleep() as Void {
        _sleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _sleeping = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        Scheduler.ensureScheduled();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var now = Time.now().value();

        dc.clearClip();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (_sleeping && _burnIn) {
            drawAlwaysOn(dc, w, h, now);
            return;
        }

        var s = dc.getFontHeight(_icons); // icon size

        drawBattery(dc, cx, (h * 0.085).toNumber(), s * 2 / 3);

        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var date = (info.day_of_week as String).toUpper() + " " + (info.day as Number).format("%d");
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.21).toNumber(), _label, date, centered());

        drawTime(dc, cx, (h * 0.45).toNumber(), !_sleeping || _partialOk);
        drawGlucoseLine(dc, cx, (h * 0.68).toNumber(), now);

        var sideL = (w * 0.115).toNumber();
        var sideR = w - sideL;
        var row1 = (h * 0.37).toNumber();
        var row2 = (h * 0.58).toNumber();
        drawStacked(dc, _slots[0], sideL, row1, s, now);
        drawStacked(dc, _slots[1], sideL, row2, s, now);
        drawStacked(dc, _slots[2], sideR, row1, s, now);
        drawStacked(dc, _slots[3], sideR, row2, s, now);

        var bottom = (h * 0.85).toNumber();
        drawInline(dc, _slots[4], (w * 0.35).toNumber(), bottom, s, now);
        drawInline(dc, _slots[5], (w * 0.65).toNumber(), bottom, s, now);
    }

    // The watch stops partial updates if they cost too much power; hide the
    // seconds in low-power mode from then on rather than show a frozen value.
    function powerBudgetExceeded() as Void {
        _partialOk = false;
    }

    // Low-power mode on MIP screens: redraw only the seconds, once a second.
    function onPartialUpdate(dc as Graphics.Dc) as Void {
        if (_burnIn || !_partialOk || _secBox[2] == 0) {
            return;
        }
        dc.setClip(_secBox[0], _secBox[1], _secBox[2], _secBox[3]);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        drawSeconds(dc);
        dc.clearClip();
    }

    // HH:MM centered with the seconds smaller and top-aligned after it; the DnD
    // moon sits in the space under the seconds.
    private function drawTime(dc as Graphics.Dc, cx as Number, cy as Number, showSeconds as Boolean) as Void {
        var hm = timeText();
        var tw = dc.getTextWidthInPixels(hm, _clock);
        var secW = dc.getTextWidthInPixels("00", _sec);
        var gap = dc.getHeight() / 80 + 1;
        var x0 = cx - (tw + gap + secW) / 2;
        var clockH = dc.getFontHeight(_clock);
        var top = cy - clockH / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, cy, _clock, hm, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var secH = dc.getFontHeight(_sec);
        _secBox = [x0 + tw + gap, top, secW + 2, secH];
        if (showSeconds) {
            drawSeconds(dc);
        }

        if (System.getDeviceSettings().doNotDisturb) {
            var mx = x0 + tw + gap + secW / 2;
            var my = top + secH + dc.getFontHeight(_icons) / 2 + 2;
            dc.setColor(0xAAAAFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(mx, my, _icons, "l", centered());
        }
    }

    private function drawSeconds(dc as Graphics.Dc) as Void {
        var sec = System.getClockTime().sec.format("%02d");
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_secBox[0], _secBox[1] + _secBox[3] / 2, _sec, sec,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // "142 ↗ +4 3m": value and arrow in the glucose color, change and age in
    // gray (age turns red once a reading is overdue).
    private function drawGlucoseLine(dc as Graphics.Dc, cx as Number, cy as Number, now as Number) as Void {
        if (!_g.hasData()) {
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, _label, noDataText(), centered());
            return;
        }

        var v = _g.lastValue();
        var age = _g.age(now);
        var late = age > Fmt.LATE_SECS;
        var sensorError = Fmt.isSensorError(v);
        var stale = age > Fmt.STALE_SECS || sensorError;
        var expired = age > Fmt.EXPIRED_SECS;

        var value = expired ? "---" : Fmt.value(v);
        var problem = null;
        if (sensorError) {
            problem = "Sensor error";
        } else if (stale) {
            problem = _g.err == Err.NETWORK ? "No phone" : "Signal loss";
        }
        var delta = stale ? "" : Fmt.delta(_g.delta());
        var ageText = Fmt.age(age);

        var lineH = dc.getFontHeight(_line);
        var arrowSize = lineH * 3 / 4;
        var showArrow = !stale && Draw.hasArrow(_g.trend);
        var gap = lineH / 4;

        var vw = dc.getTextWidthInPixels(value, _line);
        var aw = showArrow ? Draw.arrowWidth(arrowSize, _g.trend) : 0;
        var mid = problem != null ? problem : delta;
        var midFont = problem != null ? _label : _line;
        var mw = mid.length() > 0 ? dc.getTextWidthInPixels(mid, midFont) : 0;
        var agw = dc.getTextWidthInPixels(ageText, _line);
        var total = vw + (aw > 0 ? gap + aw : 0) + (mw > 0 ? gap + mw : 0) + gap + agw;
        var x = cx - total / 2;
        var j = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(stale ? FAINT : Fmt.color(v), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, cy, _line, value, j);
        x += vw;
        if (aw > 0) {
            Draw.arrow(dc, x + gap + aw / 2, cy, arrowSize, _g.trend);
            x += gap + aw;
        }
        if (mw > 0) {
            dc.setColor(problem != null ? Fmt.LATE_COLOR : DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + gap, cy, midFont, mid, j);
            x += gap + mw;
        }
        dc.setColor(late ? Fmt.LATE_COLOR : FAINT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + gap, cy, _line, ageText, j);
    }

    // Side slot: icon above value.
    private function drawStacked(dc as Graphics.Dc, id as Number, cx as Number, cy as Number, s as Number, now as Number) as Void {
        if (id == Fields.NONE) {
            return;
        }
        var fh = dc.getFontHeight(_label);
        Fields.icon(dc, _icons, id, cx, cy - fh / 2, now);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + s / 2 + 2, _label, Fields.text(id, now), centered());
    }

    // Bottom slot: icon beside value.
    private function drawInline(dc as Graphics.Dc, id as Number, cx as Number, cy as Number, s as Number, now as Number) as Void {
        if (id == Fields.NONE) {
            return;
        }
        var text = Fields.text(id, now);
        var tw = dc.getTextWidthInPixels(text, _label);
        var gap = s / 3;
        var x = cx - (s + gap + tw) / 2;
        Fields.icon(dc, _icons, id, x + s / 2, cy, now);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + s + gap, cy, _label, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Battery outline with fill level and a bolt while charging, then percent.
    private function drawBattery(dc as Graphics.Dc, cx as Number, cy as Number, s as Number) as Void {
        var stats = System.getSystemStats();
        var pct = (stats.battery + 0.5).toNumber();
        var charging = (stats has :charging) && stats.charging;
        var text = pct.format("%d") + "%";
        var tw = dc.getTextWidthInPixels(text, _label);
        var bw = s * 3 / 2;
        var bh = s * 3 / 4;
        var boltW = charging ? dc.getTextWidthInPixels("k", _icons) : 0;
        var gap = s / 3;
        var x = cx - (boltW + (charging ? gap : 0) + bw + 2 + gap + tw) / 2;

        if (charging) {
            dc.setColor(0xFFFF55, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, cy, _icons, "k", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += boltW + gap;
        }

        var fill = charging ? 0x55FF55 : (pct > 30 ? 0x55FF55 : (pct > 15 ? 0xFFAA00 : 0xFF5555));
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, cy - bh / 2, bw, bh, 2);
        dc.fillRectangle(x + bw, cy - bh / 4, 2, bh / 2);
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        var inner = (bw - 4) * pct / 100;
        if (inner > 0) {
            dc.fillRectangle(x + 2, cy - bh / 2 + 2, inner, bh - 4);
        }

        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + bw + 2 + gap, cy, _label, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // AMOLED always-on: time and the glucose value only, dim, shifted each
    // minute to avoid burn-in.
    private function drawAlwaysOn(dc as Graphics.Dc, w as Number, h as Number, now as Number) as Void {
        var shift = ((now / 60) % 5 - 2) * 3;
        var cx = w / 2 + shift;
        dc.setColor(FAINT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.45).toNumber() + shift, _clock, timeText(), centered());
        if (_g.hasData() && _g.age(now) < Fmt.EXPIRED_SECS && !Fmt.isSensorError(_g.lastValue())) {
            var v = _g.lastValue();
            dc.setColor(Fmt.color(v), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.68).toNumber() + shift, _line, Fmt.value(v), centered());
        }
    }

    private function timeText() as String {
        var ct = System.getClockTime();
        var hour = ct.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return hour.format("%d") + ":" + ct.min.format("%02d");
    }

    private function noDataText() as String {
        var e = _g.err;
        if (e == Err.NO_CREDS || !Ingest.hasCredentials()) {
            return "Set login in Connect IQ app";
        } else if (e == Err.AUTH) {
            return "Dexcom login failed";
        } else if (e == Err.LOCKED) {
            return "Dexcom account locked";
        } else if (e == Err.NETWORK) {
            return _g.code == -104 ? "No phone connection" : ("Error " + _g.code.format("%d"));
        } else if (e == Err.NO_DATA) {
            return "No readings from Dexcom";
        }
        return "Waiting for data";
    }

    private function centered() as Number {
        return Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
    }
}
