import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;

// Schedules the next background fetch for just after the next reading should
// reach Dexcom (last reading + 5 min + a learned upload delay), instead of a
// fixed 5 minute timer that drifts against the sensor's schedule.
//
// Garmin hard-limits temporal events to ≥5 minutes apart. Watch faces cannot
// fetch in the foreground — only this background schedule.
(:glance)
module Scheduler {
    const MIN_GAP = 300;
    const AUTH_RETRY_SECS = 15 * 60;

    function scheduleNext() as Void {
        var s = Application.Storage;
        if (!Ingest.hasCredentials()) {
            Background.deleteTemporalEvent();
            return;
        }

        var now = Time.now().value();

        // A single AUTH blip used to delete the schedule forever (face stuck,
        // widget still fine — separate storage). Retry after a cooldown.
        // Missing authBadAt = legacy latch → clear and retry immediately.
        if (s.getValue("authBad") == true) {
            var badAt = s.getValue("authBadAt");
            if (badAt instanceof Number && now - badAt < AUTH_RETRY_SECS) {
                registerAt(badAt + AUTH_RETRY_SECS);
                return;
            }
            s.deleteValue("authBad");
            s.deleteValue("authBadAt");
        }

        var g = new Glucose();

        // No readings yet: use a repeating 5-min Duration (Garmin's usual watch-
        // face pattern). Smarter Moment scheduling can leave a fresh install
        // sitting on "Waiting for data" if the first one-shot never fires.
        if (!g.hasData()) {
            try {
                Background.registerForTemporalEvent(new Time.Duration(MIN_GAP));
            } catch (e) {
                registerAt(now);
            }
            return;
        }

        var target = g.lastTime() + 300 + Ingest.bufferSecs();
        if (target < now) {
            target = now;
        }

        // Temporal events must be at least 5 minutes apart.
        var lastEvent = Background.getLastTemporalEventTime();
        if (lastEvent != null && target < lastEvent.value() + MIN_GAP) {
            target = lastEvent.value() + MIN_GAP;
        }
        var bgAt = s.getValue("bgAt");
        if (bgAt instanceof Number && target < bgAt + MIN_GAP && bgAt <= now) {
            target = bgAt + MIN_GAP;
        }

        registerAt(target);
    }

    function registerAt(target as Number) as Void {
        try {
            Background.registerForTemporalEvent(new Time.Moment(target));
        } catch (e) {
            try {
                Background.registerForTemporalEvent(new Time.Duration(MIN_GAP));
            } catch (e2) {
            }
        }
    }

    // Safety net: a one-shot event that already passed without delivering data
    // (e.g. the background process was killed) would otherwise stop updates.
    // When already late, also pull in a schedule that was pushed too far out.
    function ensureScheduled() as Void {
        var now = Time.now().value();
        var reg = Background.getTemporalEventRegisteredTime();
        if (reg == null) {
            scheduleNext();
            return;
        }
        if (reg instanceof Time.Moment) {
            var when = reg.value();
            if (when < now - 120) {
                scheduleNext();
                return;
            }
            var g = new Glucose();
            var late = !g.hasData() || now - g.lastTime() > Fmt.LATE_SECS;
            if (late && when > now + 60) {
                scheduleNext();
            }
        }
    }
}
