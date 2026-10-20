import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

(:background)
class GlucoseFaceApp extends Application.AppBase {
    var view = null;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        Fmt.load();
        Scheduler.scheduleNext();
        view = new GlucoseFaceView();
        return [view, new GlucoseFaceDelegate(view)];
    }

    function getServiceDelegate() {
        return [new BgService()];
    }

    function onBackgroundData(data) as Void {
        if (data instanceof Dictionary) {
            Ingest.apply(data, true);
        }
        Scheduler.scheduleNext();
        if (view != null) {
            view.dataChanged();
        }
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() as Void {
        Ingest.resetSession();
        Fmt.load();
        Scheduler.scheduleNext();
        if (view != null) {
            view.settingsChanged();
        }
        WatchUi.requestUpdate();
    }
}

class GlucoseFaceDelegate extends WatchUi.WatchFaceDelegate {
    private var _view as GlucoseFaceView;

    function initialize(view as GlucoseFaceView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPowerBudgetExceeded(info as WatchUi.WatchFacePowerInfo) as Void {
        _view.powerBudgetExceeded();
    }
}
