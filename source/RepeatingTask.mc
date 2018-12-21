class RepeatingTask {
	protected var repeats = true; // repeating?
	protected var every = 30000; // milliseconds between execution
	protected var pollerTimerName = "default"; // task name
    
    function initialize() {}
    function setup() {}
    function executeTask() {}
    function cleanup() {}

    function startTimer() {
    	if (Cron.getInstance().isEnabled(self.pollerTimerName)) {
    		return;
    	}
    	
    	Logger.getInstance().infoF("ref=repeating-task at=start-timer task=$1$", [self.pollerTimerName]);
    	self.setup();
		Cron.getInstance().register(self.pollerTimerName, self.every, self.method(:executeTask), self.repeats);
    }
    
    function stopTimer() {
    	if (!Cron.getInstance().isRegistered(self.pollerTimerName)) {
    		return;
    	}

		Logger.getInstance().infoF("ref=repeating-task at=stop-timer task=$1$", [self.pollerTimerName]);
		self.cleanup();
		Cron.getInstance().unregister(self.pollerTimerName);
    }
}

// vi:syntax=javascript filetype=javascript