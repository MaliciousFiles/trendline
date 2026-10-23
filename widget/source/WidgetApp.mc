import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

(:background, :glance)
class GlucoseWidgetApp extends Application.AppBase {
    var view = null;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        Fmt.load();
        Application.Storage.setValue("needHistory", true);
        updateBackground();
        view = new GlucoseWidgetView();
        return [view, new GlucoseWidgetDelegate(view)];
    }

    function getGlanceView() {
        Fmt.load();
        Application.Storage.setValue("needHistory", true);
        updateBackground();
        return [new GlucoseGlanceView()];
    }

    function getServiceDelegate() {
        return [new BgService()];
    }

    function onBackgroundData(data) as Void {
        if (data instanceof Dictionary) {
            Ingest.apply(data, true);
        }
        updateBackground();
        if (view != null) {
            view.dataChanged();
        }
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() as Void {
        Ingest.resetSession();
        Fmt.load();
        updateBackground();
        if (view != null) {
            view.dataChanged();
            view.refresh();
        }
        WatchUi.requestUpdate();
    }

    // Background refresh keeps the glance current. "Auto" turns it on only
    // where glances exist, since on older watches the widget fetches when opened.
    function updateBackground() as Void {
        var mode = Application.Properties.getValue("bgUpdates");
        var on = mode == 1;
        if (mode == 0 || mode == null) {
            var ds = System.getDeviceSettings();
            on = (ds has :isGlanceModeEnabled) && ds.isGlanceModeEnabled;
        }
        if (on) {
            Scheduler.scheduleNext();
        } else {
            Background.deleteTemporalEvent();
        }
    }
}
