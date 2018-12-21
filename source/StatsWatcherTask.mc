using Toybox.System;

var _statsWatcherTask;
static class StatsWatcherTask extends RepeatingTask {
	private var memCutoff = 30;

	static function getInstance() {
		if (_statsWatcherTask == null) {
			_statsWatcherTask = new StatsWatcherTask();
		}
		return _statsWatcherTask;
	}

	function initialize() {
		Logger.getInstance().info("ref=stats-watcher-task at=initialize");
		self.every = 5000;
		self.pollerTimerName = "stats-watcher";
	}
	
	function executeTask() {
		var stats = System.getSystemStats();
		var freePerc = (stats.freeMemory*1.0) / (stats.totalMemory*1.0) * 100.0;
		if (freePerc < self.memCutoff && !Logger.getInstance().isMuted()) {
			// disable logging until memory is freed
			Logger.getInstance().infoF("ref=stats-watcher at=mute mem-used=$1$ mem-free=$2$ mem-total=$3$ mem-free-perc=$4$ battery=$5$",
				[stats.usedMemory, stats.freeMemory, stats.totalMemory, freePerc, stats.battery]);
			Logger.getInstance().mute();			
		} else if (freePerc > self.memCutoff && Logger.getInstance().isMuted()) {
			// re-enable logging
			Logger.getInstance().unmute();
			Logger.getInstance().infoF("ref=stats-watcher at=unmute mem-used=$1$ mem-free=$2$ mem-total=$3$ mem-free-perc=$4$ battery=$5$",
				[stats.usedMemory, stats.freeMemory, stats.totalMemory, freePerc, stats.battery]);	
		} // else { stay in same state }
	}
}

// vi:syntax=javascript filetype=javascript