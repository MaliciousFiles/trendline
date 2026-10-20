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

// Talks to the Dexcom Share service (the same backend Dexcom Follow uses).
//
// Flow: AuthenticatePublisherAccount -> accountId
//       LoginPublisherAccountById    -> sessionId
//       ReadPublisherLatestGlucoseValues
// The account and session IDs are cached so a normal refresh is a single request.
// Login endpoints return a bare JSON string UUID; modern Connect IQ accepts that
// as HTTP_RESPONSE_CONTENT_TYPE_JSON (TEXT_PLAIN fails on device because Dexcom
// still sends Content-Type: application/json).
(:background)
class DexcomClient {
    private const APP_ID_US = "d89443d2-327c-4a6f-89e5-496bbb0317db";
    private const APP_ID_JP = "d8665ade-9673-4e27-9ff6-92db4ce13d13";
    private const NULL_UUID = "00000000-0000-0000-0000-000000000000";

    private var _callback as Method(result as Dictionary) as Void;
    private var _count as Number;
    private var _user as String = "";
    private var _pass as String = "";
    private var _base as String;
    private var _appId as String;
    private var _accountId as String? = null;
    private var _sessionId as String? = null;
    private var _retried as Boolean = false;

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
        if (region == 1) {
            _base = "https://shareous1.dexcom.com/ShareWebServices/Services/";
            _appId = APP_ID_US;
        } else if (region == 2) {
            _base = "https://share.dexcom.jp/ShareWebServices/Services/";
            _appId = APP_ID_JP;
        } else {
            _base = "https://share2.dexcom.com/ShareWebServices/Services/";
            _appId = APP_ID_US;
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
        // A previous attempt was rejected; don't retry until the settings change,
        // otherwise Dexcom will lock the account.
        if (Application.Storage.getValue("authBad") == true) {
            finish(Err.AUTH, 0);
            return;
        }
        if (_sessionId != null) {
            readGlucose();
        } else if (_accountId != null) {
            login();
        } else {
            authenticate();
        }
    }

    private function post(endpoint as String, body as Dictionary, json as Boolean, cb as Method) as Void {
        Communications.makeWebRequest(
            _base + endpoint,
            body,
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Accept" => "application/json"
                },
                :responseType => json
                    ? Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
                    : Communications.HTTP_RESPONSE_CONTENT_TYPE_TEXT_PLAIN
            },
            cb
        );
    }

    private function authenticate() as Void {
        // Login endpoints return a bare JSON string ("uuid"). Request JSON
        // (not TEXT_PLAIN): Dexcom's Content-Type is application/json, and
        // many watches reject a text/plain mismatch with -400/-401.
        post("General/AuthenticatePublisherAccount",
            { "accountName" => _user, "password" => _pass, "applicationId" => _appId },
            true, method(:onAuthenticate));
    }

    function onAuthenticate(code as Number, data) as Void {
        var id = parseId(code, data);
        if (id == null) {
            loginFailed(code, data);
            return;
        }
        _accountId = id;
        login();
    }

    private function login() as Void {
        post("General/LoginPublisherAccountById",
            { "accountId" => _accountId, "password" => _pass, "applicationId" => _appId },
            true, method(:onLogin));
    }

    function onLogin(code as Number, data) as Void {
        var id = parseId(code, data);
        if (id == null) {
            loginFailed(code, data);
            return;
        }
        _sessionId = id;
        readGlucose();
    }

    private function readGlucose() as Void {
        // minutes=1440 so the latest reading is returned even when it is stale.
        // Put params in the JSON body (not the URL); that is what works on device.
        post("Publisher/ReadPublisherLatestGlucoseValues", {
            "sessionId" => _sessionId,
            "minutes" => 1440,
            "maxCount" => _count
        }, true, method(:onGlucose));
    }

    function onGlucose(code as Number, data) as Void {
        if (code == 200 && data instanceof Array) {
            var n = data.size();
            var times = new [n];
            var values = new [n];
            var trends = new [n];
            for (var i = 0; i < n; i++) {
                var r = data[i] as Dictionary;
                times[i] = parseTime(r["WT"]);
                values[i] = r["Value"];
                trends[i] = trendCode(r["Trend"]);
            }
            data = null;
            var result = baseResult(Err.OK, code);
            result["t"] = times;
            result["v"] = values;
            result["d"] = trends;
            _callback.invoke(result);
            return;
        }

        if (code >= 400 && code < 600 && !_retried) {
            // Session expired or was invalidated: log in again once.
            _retried = true;
            _sessionId = null;
            if (_accountId != null) {
                login();
            } else {
                authenticate();
            }
            return;
        }

        finish(code < 0 ? Err.NETWORK : Err.SERVER, code);
    }

    private function loginFailed(code as Number, data) as Void {
        if (code < 0) {
            finish(Err.NETWORK, code);
            return;
        }
        var body = "";
        if (data instanceof String) {
            body = data;
        } else if (data instanceof Dictionary) {
            var c = data["Code"];
            var m = data["Message"];
            if (c instanceof String) {
                body = c;
            }
            if (m instanceof String) {
                body = body + m;
            }
        }
        if (body.find("MaxAttempts") != null) {
            finish(Err.LOCKED, code);
        } else if (body.find("AccountPasswordInvalid") != null
                || body.find("Cannot Authenticate") != null
                || body.find("accountName") != null
                || body.find("password") != null) {
            finish(Err.AUTH, code);
        } else if (_accountId != null && _retried == false) {
            // Cached account ID may be stale; start over from the username.
            _retried = true;
            _accountId = null;
            authenticate();
        } else if (code == 400 || code == 500) {
            // Dexcom answers bad credentials with 400/500. The body isn't always
            // readable here, so treat these as auth failures to avoid locking the
            // account with repeated attempts.
            finish(Err.AUTH, code);
        } else {
            finish(Err.SERVER, code);
        }
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
                // Drifting down from in range, accelerating into LOW.
                v = (39 + 110 * Math.pow(i / 35.0, 0.6) + 8 * Math.sin(i / 3.0)).toNumber();
                trend = i < 4 ? 7 : 6;
            } else if (kind.equals("high")) {
                // A post-meal climb out of range into HIGH.
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
        var result = baseResult(Err.OK, 200);
        result["t"] = times;
        result["v"] = values;
        result["d"] = trends;
        _callback.invoke(result);
    }

    private function baseResult(err as Number, code as Number) as Dictionary {
        return {
            "e" => err,
            "c" => code,
            "s" => _sessionId,
            "a" => _accountId
        };
    }

    private function finish(err as Number, code as Number) as Void {
        var result = baseResult(err, code);
        if (err == Err.AUTH || err == Err.LOCKED) {
            result["s"] = null;
            result["a"] = null;
        }
        _callback.invoke(result);
    }

    private function parseId(code as Number, data) as String? {
        if (code != 200 || !(data instanceof String)) {
            return null;
        }
        // Simulator often keeps the JSON quotes; the device usually strips them.
        var s = trim(data);
        if (s.length() >= 2 && s.substring(0, 1).equals("\"")) {
            s = s.substring(1, s.length() - 1);
        }
        if (s.length() != 36 || s.equals(NULL_UUID)) {
            return null;
        }
        return s;
    }

    // "Date(1697040000000)" -> 1697040000 (seconds)
    private function parseTime(wt) as Number {
        if (wt instanceof String) {
            var start = wt.find("(");
            if (start != null && wt.length() >= start + 11) {
                var secs = wt.substring(start + 1, start + 11).toNumber();
                if (secs != null) {
                    return secs;
                }
            }
        }
        return 0;
    }

    private function trendCode(t) as Number {
        if (t instanceof Number) {
            return t;
        }
        if (!(t instanceof String)) {
            return 0;
        }
        var names = ["None", "DoubleUp", "SingleUp", "FortyFiveUp", "Flat",
                     "FortyFiveDown", "SingleDown", "DoubleDown", "NotComputable", "RateOutOfRange"];
        for (var i = 0; i < names.size(); i++) {
            if (names[i].equals(t)) {
                return i;
            }
        }
        return 0;
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
    private var _result as Dictionary = {};

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var want = Application.Storage.getValue("want");
        if (!(want instanceof Number)) {
            want = 36; // no history yet: fill the full 3 hours
        }
        // Parsing 36 readings is too much for devices with a 32 KB background limit.
        if (want > 12 && System.getSystemStats().freeMemory < 24000) {
            want = 12;
        }
        _client = new DexcomClient(method(:onResult), want);
        _client.start();
    }

    function onResult(result as Dictionary) as Void {
        _result = result;
        if (weatherDue()) {
            var loc = Application.Storage.getValue("loc") as Array;
            result["wxTry"] = true;
            Communications.makeWebRequest(
                "https://api.open-meteo.com/v1/forecast?latitude=" + (loc[0] as Float).format("%.2f")
                    + "&longitude=" + (loc[1] as Float).format("%.2f") + "&current=temperature_2m",
                null,
                { :method => Communications.HTTP_REQUEST_METHOD_GET,
                  :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onWeather));
            return;
        }
        Background.exit(result);
    }

    function onWeather(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary) {
            var cur = data["current"];
            if (cur instanceof Dictionary && cur["temperature_2m"] != null) {
                _result["wx"] = cur["temperature_2m"];
            }
        }
        Background.exit(_result);
    }

    // Watch face temperature on watches without Garmin weather: at most every
    // 30 minutes, and only once a location is known.
    private function weatherDue() as Boolean {
        var s = Application.Storage;
        if (s.getValue("wxWant") != true || !(s.getValue("loc") instanceof Array)) {
            return false;
        }
        var last = s.getValue("wxTryAt");
        return !(last instanceof Number) || Time.now().value() - last > 30 * 60;
    }
}
