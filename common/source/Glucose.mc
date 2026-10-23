import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;

// A snapshot of the cached glucose history (oldest reading first).
(:glance)
class Glucose {
    var times as Array<Number> = [];
    var values as Array<Number> = [];
    var trend as Number = 0;
    var err as Number = 0;
    var code as Number = 0;

    function initialize() {
        reload();
    }

    function reload() as Void {
        var s = Application.Storage;
        var t = s.getValue("ht");
        var v = s.getValue("hv");
        if (t instanceof Array && v instanceof Array && t.size() == v.size()) {
            times = t as Array<Number>;
            values = v as Array<Number>;
        } else {
            times = [];
            values = [];
        }
        trend = numOr(s.getValue("tr"), 0);
        err = numOr(s.getValue("err"), 0);
        code = numOr(s.getValue("code"), 0);
    }

    function hasData() as Boolean {
        return times.size() > 0;
    }

    function lastTime() as Number {
        return times.size() > 0 ? times[times.size() - 1] : 0;
    }

    function lastValue() as Number {
        return values.size() > 0 ? values[values.size() - 1] : 0;
    }

    // Change from the previous reading, or null if there isn't a recent one.
    function delta() as Number? {
        var n = times.size();
        if (n < 2 || times[n - 1] - times[n - 2] > 450) {
            return null;
        }
        var a = values[n - 1];
        var b = values[n - 2];
        if (Fmt.isSensorError(a) || Fmt.isSensorError(b)) {
            return null;
        }
        return a - b;
    }

    function age(now as Number) as Number {
        return now - lastTime();
    }

    static function numOr(v, def as Number) as Number {
        return v instanceof Number ? v : def;
    }
}

// Merges fetch results into storage. Runs in the main process, never in the background.
(:glance)
module Ingest {
    const KEEP_SECS = 3 * 3600 + 600;
    const MAX_POINTS = 40;

    function apply(r as Dictionary, fromBackground as Boolean) as Void {
        var s = Application.Storage;
        var now = Time.now().value();

        // Weather-only background tick: don't touch glucose / err state.
        if (r["wxOnly"] == true) {
            s.deleteValue("wxPending");
            s.deleteValue("wxPendingAt");
            if (r["wxTry"] == true) {
                s.setValue("wxTryAt", now);
            }
            if (r["wx"] != null) {
                s.setValue("wx", r["wx"]);
                s.setValue("wxAt", now);
            }
            if (fromBackground) {
                s.setValue("bgAt", now);
            }
            return;
        }

        var err = Glucose.numOr(r["e"], Err.SERVER);

        s.setValue("err", err);
        s.setValue("code", Glucose.numOr(r["c"], 0));
        s.setValue("fetchAt", now);
        if (fromBackground) {
            s.setValue("bgAt", now);
        }

        if (err == Err.AUTH || err == Err.LOCKED) {
            s.setValue("authBad", true);
            s.setValue("authBadAt", now);
        } else if (err == Err.OK) {
            s.deleteValue("authBad");
            s.deleteValue("authBadAt");
        }
        storeId("sid", r["s"]);
        storeId("aid", r["a"]);
        if (r["wxNext"] == true) {
            s.setValue("wxPending", true);
            s.setValue("wxPendingAt", now);
        }
        if (r["wxTry"] == true) {
            s.setValue("wxTryAt", now);
        }
        if (r["wx"] != null) {
            s.setValue("wx", r["wx"]);
            s.setValue("wxAt", now);
        }

        if (err == Err.OK) {
            merge(r, now);
            // Dexcom answered but has no readings at all (Share off, new sensor).
            if (!(new Glucose()).hasData()) {
                s.setValue("err", Err.NO_DATA);
            }
            // Back off full-window retries for a while only when a full 3-hour
            // request still left a hole: then Dexcom really has no data there.
            // Smaller fetches (the watch face's 2, a background capped at 12)
            // say nothing about older history, so they must not block a backfill.
            var gap = HistoryWant.largestGap((new Glucose()).times, now);
            if (gap <= HistoryWant.GAP_SECS) {
                s.deleteValue("gapTry");
            } else if (Glucose.numOr(r["n"], 0) >= HistoryWant.FULL) {
                s.setValue("gapTry", now);
            }
        }
        s.setValue("want", wanted(now));
    }

    function storeId(key as String, v) as Void {
        if (v instanceof String) {
            Application.Storage.setValue(key, v);
        } else {
            Application.Storage.deleteValue(key);
        }
    }

    function merge(r as Dictionary, now as Number) as Void {
        var s = Application.Storage;
        var g = new Glucose();
        var ht = g.times;
        var hv = g.values;
        var prevLast = g.lastTime();

        var t = r["t"] as Array;
        var v = r["v"] as Array;
        var d = r["d"] as Array;
        var newestTime = 0;
        var newestTrend = 0;

        for (var i = 0; i < t.size(); i++) {
            var ti = t[i];
            var vi = v[i];
            if (!(ti instanceof Number) || !(vi instanceof Number) || ti <= 0) {
                continue;
            }
            if (ti > newestTime) {
                newestTime = ti;
                newestTrend = d[i];
            }
            insertSorted(ht, hv, ti, vi);
        }

        if (ht.size() > 0) {
            var cutoff = ht[ht.size() - 1] - KEEP_SECS;
            var drop = 0;
            while (drop < ht.size() && (ht[drop] < cutoff || ht.size() - drop > MAX_POINTS)) {
                drop++;
            }
            if (drop > 0) {
                ht = ht.slice(drop, null);
                hv = hv.slice(drop, null);
            }
        }

        s.setValue("ht", ht);
        s.setValue("hv", hv);
        if (newestTime > 0 && newestTime >= prevLast) {
            s.setValue("tr", newestTrend);
        }

        learnBuffer(prevLast, ht.size() > 0 ? ht[ht.size() - 1] : 0, now);
    }

    function insertSorted(ht as Array<Number>, hv as Array<Number>, t as Number, v as Number) as Void {
        var i = ht.size();
        while (i > 0 && ht[i - 1] > t + 30) {
            i--;
        }
        if (i > 0 && ht[i - 1] >= t - 30) {
            return; // already have this reading
        }
        ht.add(t);
        hv.add(v);
        for (var k = ht.size() - 1; k > i; k--) {
            ht[k] = ht[k - 1];
            hv[k] = hv[k - 1];
        }
        ht[i] = t;
        hv[i] = v;
    }

    // Tunes how long after the expected reading time we wait before fetching.
    // Too short and the reading hasn't reached Dexcom yet (costing a 5 min wait);
    // too long and the display is needlessly stale. Probe down slowly, back off fast.
    function learnBuffer(prevLast as Number, newLast as Number, now as Number) as Void {
        if (prevLast <= 0) {
            return;
        }
        var buf = bufferSecs();
        var expected = prevLast + 300;
        if (now < expected || now > expected + buf + 90) {
            return; // this fetch wasn't timed for the next reading
        }
        if (newLast > prevLast + 30) {
            buf -= 3;
        } else {
            buf += 30;
        }
        if (buf < 15) {
            buf = 15;
        } else if (buf > 180) {
            buf = 180;
        }
        Application.Storage.setValue("buf", buf);
    }

    function wanted(now as Number) as Number {
        return HistoryWant.compute(now);
    }

    function bufferSecs() as Number {
        return Glucose.numOr(Application.Storage.getValue("buf"), 45);
    }

    function hasCredentials() as Boolean {
        var u = Application.Properties.getValue("username");
        var p = Application.Properties.getValue("password");
        if (u instanceof String && u.find("demo") == 0) {
            return true;
        }
        return u instanceof String && u.length() > 0 && p instanceof String && p.length() > 0;
    }

    // Called when the user edits settings: credentials may have changed.
    function resetSession() as Void {
        var s = Application.Storage;
        s.deleteValue("sid");
        s.deleteValue("aid");
        s.deleteValue("authBad");
        s.deleteValue("authBadAt");
        s.deleteValue("gapTry");
        s.setValue("err", Err.OK);
    }

    // Seconds until the next reading is expected (negative when overdue).
    function secondsUntilNext(g as Glucose, now as Number) as Number {
        return g.lastTime() + 300 - now;
    }
}

// Shared by the UI and the background service (Dexcom only returns newest N).
// Watch face sets Storage "needHistory" = false (tip only); widget sets true.
(:background, :glance)
module HistoryWant {
    const GAP_SECS = 450;     // more than one missed reading
    const WINDOW = 3 * 3600;  // the widget graph
    const FULL = 36;          // readings in WINDOW

    function compute(now as Number) as Number {
        // Face only shows the latest reading (+ prior for delta) — never pull 3h.
        if (Application.Storage.getValue("needHistory") != true) {
            return 2;
        }

        var t = Application.Storage.getValue("ht");
        if (!(t instanceof Array) || t.size() == 0) {
            return FULL;
        }
        var times = t as Array<Number>;
        var tip = (now - times[times.size() - 1]) / 300 + 2;
        if (tip < 2) {
            tip = 2;
        } else if (tip > FULL) {
            tip = FULL;
        }

        // Complete 3 hours: just top up the newest readings.
        if (largestGap(times, now) <= GAP_SECS) {
            return tip;
        }
        // Something is missing (left edge, middle or right edge). Dexcom only
        // returns the newest N, so ask for the whole window, unless a full
        // request recently came back with the same hole.
        var tried = Application.Storage.getValue("gapTry");
        if (tried instanceof Number && now - tried < 15 * 60) {
            return tip;
        }
        return FULL;
    }

    // Largest stretch of the 3-hour window without a reading, including before
    // the oldest stored reading and after the newest.
    function largestGap(times as Array<Number>, now as Number) as Number {
        var t0 = now - WINDOW;
        var prev = t0;
        var maxGap = 0;
        for (var i = 0; i < times.size(); i++) {
            var ti = times[i];
            if (ti < t0) {
                continue;
            }
            if (ti - prev > maxGap) {
                maxGap = ti - prev;
            }
            prev = ti;
        }
        if (now - prev > maxGap) {
            maxGap = now - prev;
        }
        return maxGap;
    }
}
