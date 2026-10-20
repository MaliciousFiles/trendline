import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Glucose history as a smooth curve whose color follows the value along its
// length, with dashed low/high guides and labels on the peak and trough.
module Graph {
    const GUIDE = 0x555555;
    const STEPS = 4;      // curve subdivisions between readings
    const MAX_GAP = 720;  // break the line across gaps longer than 12 minutes

    // rect is [x, y, width, height].
    function draw(dc as Graphics.Dc, rect as Array<Number>, g as Glucose, now as Number,
                  spanSecs as Number, pen as Number, labels as Boolean) as Void {
        var x = rect[0];
        var y = rect[1];
        var w = rect[2];
        var h = rect[3];
        var t0 = now - spanSecs;

        // Readings inside the window, in screen space.
        var xs = [];
        var ys = [];
        var vs = [];
        var ts = [];
        var minV = 999;
        var maxV = 0;
        for (var i = 0; i < g.times.size(); i++) {
            if (g.times[i] >= t0 && !Fmt.isSensorError(g.values[i])) {
                var v = g.values[i];
                ts.add(g.times[i]);
                vs.add(v);
                minV = v < minV ? v : minV;
                maxV = v > maxV ? v : maxV;
            }
        }

        // Scale to the data, always keeping both guide lines in view.
        var lo = Fmt.low - 25;
        var hi = Fmt.high + 25;
        if (vs.size() > 0) {
            lo = minV - 15 < lo ? minV - 15 : lo;
            hi = maxV + 15 > hi ? maxV + 15 : hi;
        }
        lo = lo < 30 ? 30 : lo;

        for (var i = 0; i < ts.size(); i++) {
            xs.add(x + (ts[i] - t0) * w / spanSecs);
            ys.add(yOf(vs[i], y, h, lo, hi));
        }

        // Guides.
        var yHigh = yOf(Fmt.high, y, h, lo, hi);
        var yLow = yOf(Fmt.low, y, h, lo, hi);
        dc.setPenWidth(1);
        dc.setColor(GUIDE, Graphics.COLOR_TRANSPARENT);
        dashed(dc, x, yHigh, w);
        dashed(dc, x, yLow, w);
        if (labels) {
            var j = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w + 4, yHigh, Graphics.FONT_XTINY, Fmt.value(Fmt.high), j);
            dc.drawText(x + w + 4, yLow, Graphics.FONT_XTINY, Fmt.value(Fmt.low), j);
        }

        var n = xs.size();
        if (n == 0) {
            return;
        }

        var aa = dc has :setAntiAlias;
        if (aa) {
            dc.setAntiAlias(true);
        }
        dc.setPenWidth(pen);
        var r = pen / 2;

        for (var i = 0; i < n - 1; i++) {
            if (ts[i + 1] - ts[i] > MAX_GAP) {
                continue;
            }
            var p0 = (i > 0 && ts[i] - ts[i - 1] <= MAX_GAP) ? i - 1 : i;
            var p3 = (i + 2 < n && ts[i + 2] - ts[i + 1] <= MAX_GAP) ? i + 2 : i + 1;
            var px = xs[i];
            var py = ys[i];
            for (var s = 1; s <= STEPS; s++) {
                var u = s.toFloat() / STEPS;
                var nx = spline(xs[p0], xs[i], xs[i + 1], xs[p3], u);
                var ny = spline(ys[p0], ys[i], ys[i + 1], ys[p3], u);
                ny = ny < y ? y : (ny > y + h ? y + h : ny);
                var v = vs[i] + (vs[i + 1] - vs[i]) * (s - 0.5) / STEPS;
                dc.setColor(Fmt.color(v.toNumber()), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(px, py, nx, ny);
                if (!aa && r > 0) {
                    dc.fillCircle(nx, ny, r); // round the joints
                }
                px = nx;
                py = ny;
            }
        }

        // Isolated readings (no neighbor within MAX_GAP) still get a dot.
        for (var i = 0; i < n; i++) {
            var before = i > 0 && ts[i] - ts[i - 1] <= MAX_GAP;
            var after = i < n - 1 && ts[i + 1] - ts[i] <= MAX_GAP;
            if (!before && !after) {
                dc.setColor(Fmt.color(vs[i]), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(xs[i], ys[i], r + 1);
            }
        }

        // Latest reading.
        dc.setColor(Fmt.color(vs[n - 1]), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(xs[n - 1], ys[n - 1], pen + 1);

        if (labels && maxV - minV >= 25) {
            labelExtreme(dc, xs, ys, vs, maxV, true, x, w, pen);
            labelExtreme(dc, xs, ys, vs, minV, false, x, w, pen);
        }

        dc.setPenWidth(1);
        if (aa) {
            dc.setAntiAlias(false);
        }
    }

    function labelExtreme(dc as Graphics.Dc, xs as Array, ys as Array, vs as Array, v as Number,
                          above as Boolean, x as Number, w as Number, pen as Number) as Void {
        var i = vs.indexOf(v);
        if (i < 0 || vs[vs.size() - 1] == v) {
            return; // the latest reading is already shown as the big number
        }
        var text = Fmt.value(v);
        var font = Graphics.FONT_XTINY;
        var half = dc.getTextWidthInPixels(text, font) / 2;
        var fh = dc.getFontHeight(font);
        var ly = above ? ys[i] - pen - fh / 2 : ys[i] + pen + fh / 2;

        // Keep the label on the graph and, on round screens, inside the circle
        // at the label's height (checking its top and bottom edges).
        var left = x + half;
        var right = x + w - half;
        if (System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND) {
            var sw = dc.getWidth();
            var r = sw / 2;
            var dy1 = (ly - fh / 2 - dc.getHeight() / 2).abs();
            var dy2 = (ly + fh / 2 - dc.getHeight() / 2).abs();
            var dy = dy1 > dy2 ? dy1 : dy2;
            if (dy < r) {
                var hw = Math.sqrt(r * r - dy * dy).toNumber() - 3;
                left = left > r - hw + half ? left : r - hw + half;
                right = right < r + hw - half ? right : r + hw - half;
            }
        }
        var lx = xs[i];
        lx = lx < left ? left : (lx > right ? right : lx);
        dc.setColor(Fmt.color(v), Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx, ly, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Catmull-Rom interpolation between p1 and p2.
    function spline(p0 as Numeric, p1 as Numeric, p2 as Numeric, p3 as Numeric, u as Float) as Number {
        var u2 = u * u;
        var u3 = u2 * u;
        var v = 0.5 * (2 * p1 + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2
            + (3 * p1 - p0 - 3 * p2 + p3) * u3);
        return (v + 0.5).toNumber();
    }

    function yOf(v as Number, y as Number, h as Number, lo as Number, hi as Number) as Number {
        if (v < lo) {
            v = lo;
        } else if (v > hi) {
            v = hi;
        }
        return y + h - (v - lo) * h / (hi - lo);
    }

    function dashed(dc as Graphics.Dc, x as Number, y as Number, w as Number) as Void {
        for (var xx = x; xx < x + w; xx += 6) {
            dc.drawLine(xx, y, xx + 3, y);
        }
    }
}
