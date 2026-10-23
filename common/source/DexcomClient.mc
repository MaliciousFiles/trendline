import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

// Error codes shared between the background fetch and the UI.
(:background, :glance)
module Err {
    const OK = 0;
    const NO_CREDS = 1;
    const AUTH = 2;
    const LOCKED = 3;
    const NETWORK = 4;
    const SERVER = 5;
    const NO_DATA = 6;
}

// Fetches glucose through a tiny HTTPS proxy (proxy/worker.js).
//
// Connect IQ's makeWebRequest only accepts JSON *objects*. Dexcom's login
// endpoints return a bare UUID string and the glucose call returns an array,
// both of which become -400 on a real watch (the simulator is more lenient).
// The proxy talks to Dexcom and returns one object the watch can parse.
(:background)
class DexcomClient {
    // Deploy with: cd proxy && npx wrangler deploy
    // Then put the workers.dev URL here (must end with /v1/glucose).
    private const PROXY_URL = "https://trendline-dexcom.mtroalson.workers.dev/v1/glucose";

    private var _callback as Method(result as Dictionary) as Void;
    private var _count as Number;
    private var _user as String = "";
    private var _pass as String = "";
    private var _region as Number = 0;
    private var _accountId as String? = null;
    private var _sessionId as String? = null;

    function initialize(callback as Method(result as Dictionary) as Void, count as Number) {
        _callback = callback;
        _count = count;

        var user = Application.Properties.getValue("username");
        var pass = Application.Properties.getValue("password");
        if (user instanceof String) {
            _user = trim(user);
        }
        if (pass instanceof String) {
            _pass = pass;
        }

        var region = Application.Properties.getValue("region");
        if (region instanceof Number) {
            _region = region;
        }

        _accountId = Application.Storage.getValue("aid") as String?;
        _sessionId = Application.Storage.getValue("sid") as String?;
    }

    function start() as Void {
        if (_user.find("demo") == 0) {
            var kind = _user.substring(4, _user.length());
            var picked = Application.Storage.getValue("demoKind");
            if (kind.length() == 0 && picked instanceof String) {
                kind = picked;
            }
            demo(kind);
            return;
        }
        if (_user.length() == 0 || _pass.length() == 0) {
            finish(Err.NO_CREDS, 0);
            return;
        }
        // Honor auth cooldown. Only the main process clears the flag (Scheduler
        // after the cooldown, Ingest on success): on older watches (API 3.1) the
        // background process can read storage but crashes if it writes.
        if (Application.Storage.getValue("authBad") == true) {
            var badAt = Application.Storage.getValue("authBadAt");
            if (badAt instanceof Number && Time.now().value() - badAt < 15 * 60) {
                finish(Err.AUTH, 0);
                return;
            }
        }
        fetchProxy();
    }

    private function fetchProxy() as Void {
        var body = {
            "u" => _user,
            "p" => _pass,
            "r" => _region,
            "n" => _count
        };
        if (_accountId != null) {
            body["a"] = _accountId;
        }
        if (_sessionId != null) {
            body["s"] = _sessionId;
        }
        Communications.makeWebRequest(
            PROXY_URL,
            body,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onProxy)
        );
    }

    function onProxy(code as Number, data as Dictionary or String or Null) as Void {
        if (code < 0) {
            finish(Err.NETWORK, code);
            return;
        }
        if (!(data instanceof Dictionary)) {
            finish(Err.SERVER, code);
            return;
        }
        var err = numOr(data["e"], Err.SERVER);
        var result = {
            "e" => err,
            "c" => numOr(data["c"], code),
            "s" => data["s"],
            "a" => data["a"]
        };
        result["n"] = _count;
        if (err == Err.OK) {
            result["t"] = data["t"];
            result["v"] = data["v"];
            result["d"] = data["d"];
        }
        _callback.invoke(result);
    }

    // Usernames starting with "demo" produce synthetic data, for the simulator,
    // screenshots and store reviewers without a Dexcom account:
    //   demo       smooth swings through low, in range and high
    //   demolow    falling to LOW        demohigh   rising to HIGH
    //   demogap    signal loss: latest reading 25 minutes old
    //   demoerror  sensor error codes for the last two readings
    //   demoempty  account with no readings
    private function demo(kind as String) as Void {
        var now = Time.now().value();
        var latest = now - 90;
        if (kind.equals("gap")) {
            latest -= 25 * 60;
        }
        var n = kind.equals("empty") ? 0 : _count;
        var times = new [n];
        var values = new [n];
        var trends = new [n];
        for (var i = 0; i < n; i++) {
            var t = latest - i * 300;
            var v;
            var trend;
            if (kind.equals("low")) {
                v = (39 + 110 * Math.pow(i / 35.0, 0.6) + 8 * Math.sin(i / 3.0)).toNumber();
                trend = i < 4 ? 7 : 6;
            } else if (kind.equals("high")) {
                v = (401 - 260 * Math.pow(i / 35.0, 0.7) + 6 * Math.sin(i / 2.5)).toNumber();
                trend = i < 4 ? 1 : 2;
            } else {
                var phase = (t / 300) % 72;
                v = (150 + 95 * Math.sin(phase * Math.PI / 36.0)).toNumber();
                var slope = Math.cos(phase * Math.PI / 36.0);
                trend = slope > 0.7 ? 2 : (slope > 0.25 ? 3 : (slope > -0.25 ? 4 : (slope > -0.7 ? 5 : 6)));
            }
            times[i] = t;
            values[i] = v < 39 ? 39 : (v > 401 ? 401 : v);
            if (kind.equals("error") && i < 2) {
                values[i] = 1;
                trend = 8;
            }
            trends[i] = trend;
        }
        var result = {
            "e" => Err.OK,
            "c" => 200,
            "s" => null,
            "a" => null,
            "n" => _count,
            "t" => times,
            "v" => values,
            "d" => trends
        };
        _callback.invoke(result);
    }

    private function finish(err as Number, code as Number) as Void {
        var result = {
            "e" => err,
            "c" => code,
            "s" => err == Err.AUTH || err == Err.LOCKED ? null : _sessionId,
            "a" => err == Err.AUTH || err == Err.LOCKED ? null : _accountId
        };
        _callback.invoke(result);
    }

    private function numOr(v, def as Number) as Number {
        return v instanceof Number ? v : def;
    }

    private function trim(s as String) as String {
        var start = 0;
        var end = s.length();
        while (start < end && s.substring(start, start + 1).equals(" ")) {
            start++;
        }
        while (end > start && s.substring(end - 1, end).equals(" ")) {
            end--;
        }
        return s.substring(start, end);
    }
}

(:background)
class BgService extends System.ServiceDelegate {
    private var _client as DexcomClient?;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        // Weather runs on its own tick so it can never block / OOM a glucose exit.
        if (fetchWeatherIfPending()) {
            return;
        }
        // Read-only here: the main process stores "want" after each result.
        var want = HistoryWant.compute(Time.now().value());
        // Widget history pulls: VA3-class heaps can't parse a full 3h payload.
        if (want > 12 && System.getSystemStats().freeMemory < 24000) {
            want = 12;
        }
        _client = new DexcomClient(method(:onResult), want);
        _client.start();
    }

    function onResult(result as Dictionary) as Void {
        // Always deliver glucose first. Ask the main process to queue weather
        // for the next 5-min slot (the background can't write storage itself).
        if (weatherWanted()) {
            result["wxNext"] = true;
        }
        Background.exit(result);
    }

    function onWeather(code as Number, data as Dictionary or String or Null) as Void {
        var out = {
            "e" => Err.OK,
            "c" => code,
            "wxOnly" => true,
            "wxTry" => true
        };
        if (code == 200 && data instanceof Dictionary) {
            var cur = data["current"];
            if (cur instanceof Dictionary && cur["temperature_2m"] != null) {
                out["wx"] = cur["temperature_2m"];
            }
        }
        Background.exit(out);
    }

    private function fetchWeatherIfPending() as Boolean {
        var s = Application.Storage;
        if (!pendingFresh() || !weatherWanted()) {
            return false;
        }
        var loc = s.getValue("loc") as Array;
        Communications.makeWebRequest(
            "https://api.open-meteo.com/v1/forecast?latitude=" + (loc[0] as Float).format("%.2f")
                + "&longitude=" + (loc[1] as Float).format("%.2f") + "&current=temperature_2m",
            null,
            { :method => Communications.HTTP_REQUEST_METHOD_GET,
              :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
            method(:onWeather));
        return true;
    }

    // Weather queued by the main process within the last 20 minutes. The
    // expiry means a weather request that never reports back can't keep
    // displacing glucose fetches.
    private function pendingFresh() as Boolean {
        var s = Application.Storage;
        var at = s.getValue("wxPendingAt");
        return s.getValue("wxPending") == true && at instanceof Number && Time.now().value() - at < 20 * 60;
    }

    // Open-Meteo when temperature is shown, a location is known, and the cache
    // is older than 30 minutes (or a glucose fetch just queued wxPending).
    private function weatherWanted() as Boolean {
        var s = Application.Storage;
        if (s.getValue("wxWant") != true || !(s.getValue("loc") instanceof Array)) {
            return false;
        }
        if (pendingFresh()) {
            return true;
        }
        var last = s.getValue("wxTryAt");
        return !(last instanceof Number) || Time.now().value() - last > 30 * 60;
    }
}
