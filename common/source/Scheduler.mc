import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;

// Schedules the next background fetch for just after the next reading should
// reach Dexcom (last reading + 5 min + a learned upload delay), instead of a
// fixed 5 minute timer that drifts against the sensor's schedule.
(:glance)
module Scheduler {
    const MIN_GAP = 300;

    function scheduleNext() as Void {
        var s = Application.Storage;
        if (s.getValue("authBad") == true || !Ingest.hasCredentials()) {
            Background.deleteTemporalEvent();
            return;
        }

        var now = Time.now().value();
        var g = new Glucose();
        var target = now;

        if (g.hasData()) {
            target = g.lastTime() + 300 + Ingest.bufferSecs();
            if (target < now) {
                target = now;
                // Feed has been quiet for a while (phone away, sensor warm-up):
                // check every 10 minutes instead of 5 to save battery.
                var bgAt = s.getValue("bgAt");
                if (now - g.lastTime() > 20 * 60 && bgAt instanceof Number && bgAt + 600 > target) {
                    target = bgAt + 600;
                }
            }
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
    function ensureScheduled() as Void {
        var reg = Background.getTemporalEventRegisteredTime();
        if (reg == null) {
            scheduleNext();
        } else if (reg instanceof Time.Moment && reg.value() < Time.now().value() - 120) {
            scheduleNext();
        }
    }
}
