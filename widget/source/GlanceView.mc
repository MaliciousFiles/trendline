import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

(:glance)
class GlucoseGlanceView extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var g = new Glucose();
        var h = dc.getHeight();
        var now = Time.now().value();

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h / 4, Graphics.FONT_XTINY, "TRENDLINE",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var cy = h * 2 / 3;
        if (!g.hasData()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, cy, Graphics.FONT_TINY, g.err == Err.NO_CREDS ? "Set up login" : "No data",
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var v = g.lastValue();
        var age = g.age(now);
        if (Fmt.isSensorError(v)) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, cy, Graphics.FONT_TINY, "Sensor error",
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var late = age > Fmt.LATE_SECS;
        var stale = age > Fmt.STALE_SECS;
        var text = Fmt.value(v);
        // Words (HIGH/LOW) are much wider than digits; use a smaller font so
        // the arrow and age still fit in the glance strip.
        var font = Fmt.isWord(v) ? Graphics.FONT_TINY : Graphics.FONT_MEDIUM;
        var tw = dc.getTextWidthInPixels(text, font);

        dc.setColor(stale ? 0xAAAAAA : Fmt.color(v), Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, cy, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var x = tw + 4;
        var size = dc.getFontHeight(font) * 2 / 3;
        if (age < Fmt.EXPIRED_SECS && Draw.hasArrow(g.trend)) {
            var aw = Draw.arrowWidth(size, g.trend);
            Draw.arrow(dc, x + aw / 2, cy, size, g.trend);
            x += aw + 8;
        }

        // Delta stays dim; only the age turns red once a reading is overdue.
        var d = Fmt.delta(g.delta());
        var sub = Graphics.FONT_XTINY;
        if (d.length() > 0) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            var ds = d + "  ";
            dc.drawText(x, cy, sub, ds, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(ds, sub);
        }
        dc.setColor(late ? Fmt.LATE_COLOR : 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, cy, sub, Fmt.age(age),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
