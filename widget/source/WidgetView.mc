import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class GlucoseWidgetView extends WatchUi.View {
    private const DIM = 0xAAAAAA;
    private const FAINT = 0x555555;

    private var _g as Glucose;
    private var _timer as Timer.Timer? = null;
    private var _client as DexcomClient? = null;
    private var _fetching as Boolean = false;
    private var _lastAttempt as Number = 0;
    private var _round as Boolean = true;
    private var _hero as Graphics.FontType = Graphics.FONT_NUMBER_HOT;
    private var _small as Graphics.FontType = Graphics.FONT_XTINY;
    private var _word as Graphics.FontType = Graphics.FONT_MEDIUM;

    function initialize() {
        View.initialize();
        _g = new Glucose();
        _round = System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _hero = WatchUi.loadResource(Rez.Fonts.Hero) as Graphics.FontType;
        _small = WatchUi.loadResource(Rez.Fonts.Small) as Graphics.FontType;
        _word = WatchUi.loadResource(Rez.Fonts.Word) as Graphics.FontType;
    }

    function onShow() as Void {
        _g.reload();
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
        maybeFetch();
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        maybeFetch();
        WatchUi.requestUpdate();
    }

    function dataChanged() as Void {
        _g.reload();
    }

    // Manual refresh (tap / select). In demo mode this cycles through test states.
    function refresh() as Void {
        if (_fetching) {
            return;
        }
        var user = Application.Properties.getValue("username");
        if (user instanceof String && user.equals("demo")) {
            var kinds = ["", "low", "high", "gap", "error", "empty"];
            var picked = Application.Storage.getValue("demoKind");
            var cur = -1;
            for (var i = 0; i < kinds.size(); i++) {
                if (picked instanceof String && kinds[i].equals(picked)) {
                    cur = i;
                }
            }
            Application.Storage.setValue("demoKind", kinds[(cur + 1) % kinds.size()]);
            Application.Storage.deleteValue("ht");
            Application.Storage.deleteValue("hv");
            Application.Storage.setValue("want", 36);
            _g.reload();
        }
        fetch();
    }

    private function maybeFetch() as Void {
        if (_fetching) {
            return;
        }
        var now = Time.now().value();
        if (_g.err == Err.AUTH || _g.err == Err.LOCKED || _g.err == Err.NO_CREDS) {
            if (_lastAttempt == 0) {
                fetch(); // re-check once on open in case settings were fixed
            }
            return;
        }
        var due = !_g.hasData() || now >= _g.lastTime() + 300 + Ingest.bufferSecs();
        var retryGap = (_g.hasData() && now - _g.lastTime() > 15 * 60) ? 60 : 20;
        if (due && now - _lastAttempt >= retryGap) {
            fetch();
        }
    }

    private function fetch() as Void {
        _fetching = true;
        _lastAttempt = Time.now().value();
        var want = Glucose.numOr(Application.Storage.getValue("want"), 36);
        _client = new DexcomClient(method(:onResult), want);
        _client.start();
        WatchUi.requestUpdate();
    }

    function onResult(result as Dictionary) as Void {
        _fetching = false;
        _client = null;
        Ingest.apply(result, false);
        _g.reload();
        var app = Application.getApp() as GlucoseWidgetApp;
        app.updateBackground();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var now = Time.now().value();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (!_g.hasData()) {
            drawMessage(dc, cx, h / 2);
            return;
        }

        var v = _g.lastValue();
        var age = _g.age(now);
        var late = age > Fmt.LATE_SECS;
        var sensorError = Fmt.isSensorError(v);
        var stale = age > Fmt.STALE_SECS || sensorError;
        var expired = age > Fmt.EXPIRED_SECS;
        var color = stale ? FAINT : Fmt.color(v);

        drawRing(dc, w, h, age, late ? Fmt.LATE_COLOR : color);

        // Countdown to the next reading; red once it's overdue.
        var until = Ingest.secondsUntilNext(_g, now);
        var status = until >= 0 ? Fmt.countdown(until) : "due " + Fmt.elapsed(-until);
        dc.setColor(late ? Fmt.LATE_COLOR : DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.12).toNumber(), _small, status,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // BIG NUMBER | arrow over change, centered as one group.
        var text = expired ? "---" : Fmt.value(v);
        var font = (!expired && Fmt.isWord(v)) ? _word : _hero;
        var tw = dc.getTextWidthInPixels(text, font);
        var arrowSize = (h * 0.09).toNumber();
        // Keep the last trend arrow and delta during signal loss; only hide
        // them for sensor errors or once the reading is too old to show.
        var showArrow = !expired && !sensorError && Draw.hasArrow(_g.trend);
        var delta = (!expired && !sensorError) ? Fmt.delta(_g.delta()) : "";
        var aw = showArrow ? Draw.arrowWidth(arrowSize, _g.trend) : 0;
        var dw = delta.length() > 0 ? dc.getTextWidthInPixels(delta, _small) : 0;
        var colW = aw > dw ? aw : dw;
        var gap = colW > 0 ? arrowSize / 3 : 0;
        var x0 = (w - tw - gap - colW) / 2;
        var cy = (h * 0.29).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, cy, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var colX = x0 + tw + gap + colW / 2;
        if (showArrow) {
            var ay = delta.length() > 0 ? cy - arrowSize * 2 / 5 : cy;
            Draw.arrow(dc, colX, ay, arrowSize, _g.trend);
        }
        if (delta.length() > 0) {
            var dy = showArrow ? cy + arrowSize * 3 / 5 : cy;
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(colX, dy, _small, delta, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var problem = null;
        if (sensorError) {
            problem = "Sensor error";
        } else if (stale) {
            problem = _g.err == Err.NETWORK ? "No phone connection" : "Signal loss";
        }
        if (problem != null) {
            dc.setColor(Fmt.LATE_COLOR, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.47).toNumber(), Graphics.FONT_XTINY, problem,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // 3 hour history.
        var gx = (w * 0.14).toNumber();
        var gw = (w * 0.61).toNumber();
        var gy = (h * 0.58).toNumber();
        var gh = (h * 0.24).toNumber();
        var pen = w >= 360 ? 3 : 2;
        Graph.draw(dc, [gx, gy, gw, gh], _g, now, 3 * 3600, pen, true);

        // Problem with the latest fetch, while still showing cached data.
        if (_g.err != Err.OK && !_fetching && !(stale && _g.err == Err.NETWORK)) {
            dc.setColor(0xFFAA00, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.90).toNumber(), Graphics.FONT_XTINY, shortError(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Progress toward the next reading (5 min), drawn around the bezel or along
    // the top edge on rectangular screens. Full once the reading is overdue.
    private function drawRing(dc as Graphics.Dc, w as Number, h as Number, age as Number, color as Number) as Void {
        var frac = age.toFloat() / 300;
        if (frac > 1.0) {
            frac = 1.0;
        } else if (frac < 0.0) {
            frac = 0.0;
        }
        var pen = w >= 360 ? 4 : 2;
        var aa = dc has :setAntiAlias;
        if (aa) {
            dc.setAntiAlias(true);
        }
        dc.setPenWidth(pen);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (_round) {
            var r = w / 2 - pen / 2 - 1;
            if (frac >= 0.999) {
                dc.drawCircle(w / 2, h / 2, r);
            } else if (frac > 0.003) {
                dc.drawArc(w / 2, h / 2, r, Graphics.ARC_CLOCKWISE, 90, 90 - (360 * frac).toNumber());
            }
        } else {
            dc.fillRectangle(0, 0, (w * frac).toNumber(), pen);
        }
        dc.setPenWidth(1);
        if (aa) {
            dc.setAntiAlias(false);
        }
    }

    private function drawMessage(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        var msg;
        if (_fetching) {
            msg = "Loading...";
        } else {
            msg = longError();
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Graphics.FONT_SMALL, msg,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function longError() as String {
        var e = _g.err;
        if (e == Err.NO_CREDS) {
            return "Add your Dexcom\nShare login in\nConnect IQ settings";
        } else if (e == Err.AUTH) {
            return "Login failed.\nCheck username\nand password";
        } else if (e == Err.LOCKED) {
            return "Dexcom locked\nthe account.\nTry again later";
        } else if (e == Err.NETWORK) {
            return "No connection\nto phone";
        } else if (e == Err.SERVER) {
            return "Dexcom error\n" + _g.code.format("%d");
        } else if (e == Err.NO_DATA) {
            return "No readings from\nDexcom Share.\nIs Share turned on?";
        }
        return "Tap to load";
    }

    private function shortError() as String {
        var e = _g.err;
        if (e == Err.AUTH) {
            return "login failed";
        } else if (e == Err.LOCKED) {
            return "account locked";
        } else if (e == Err.NETWORK) {
            return "no phone connection";
        } else if (e == Err.NO_CREDS) {
            return "no login set";
        } else if (e == Err.NO_DATA) {
            return "no readings";
        }
        return "dexcom error " + _g.code.format("%d");
    }
}

class GlucoseWidgetDelegate extends WatchUi.BehaviorDelegate {
    private var _view as GlucoseWidgetView;

    function initialize(view as GlucoseWidgetView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        _view.refresh();
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _view.refresh();
        return true;
    }
}
