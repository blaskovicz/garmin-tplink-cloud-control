using Toybox.WatchUi as Ui;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Communications as Comm;
using Toybox.System;
using Env;

var _api;

// Singleton NestApi:

// TODO: buffer, splay and retry request to handle BLE QUEUE FULL error (code -101)
// TODO also a way of queueing or handlying multiple request/response pairs
static class NestApi {
	static const unusedCameraFields = ["app_url", "web_url", "last_event", "where_id", "where_name", "structure_id", "software_version", "name_long", "last_is_online_change", "is_video_history_enabled", "is_audio_input_enabled"];

	enum {
		StateRequestError = 0,
		StateRequesting = 1,
		StateRequestSuccess = 2
	}
	
	protected var debounceResultsTimerName = "api-results";
	protected var pollerTimerName = "api-poller";
	protected var cancelOauthTimerName = "cancel-oauth-connect";
	
	protected var temp;
	protected var state; // eg { :state => StateRequestError, :text => "some description" }
	protected var pollerState; // same as above, but seperate so we don't conflict with user-requested actions
	
	protected var camerasUpdatedAt;
	protected var cameraList;
		
	protected var connecting;
		
	static function getInstance() {
		if (_api == null) {
			_api = new NestApi();
		}
		return _api;
	}

	function initialize() {
		Logger.getInstance().info("ref=nest-api at=initialize");
		Comm.registerForOAuthMessages(self.method(:onOauthResponsePhase1));
	}
	
	function getState() {
		return self.state;
	}
	
	function getPollerState() {
		return self.pollerState;
	}
	
	// debounce update requests and give us a few millis to finish
	// writing data to self
	protected function notifyResults() {
		if (Cron.getInstance().isEnabled(debounceResultsTimerName)) {
			return;
		}
		
		Cron.getInstance().register(debounceResultsTimerName, 300, self.method(:flushNotify), false);
	}
	
	function flushNotify() {		
		Ui.requestUpdate();
	}
	
	function clearState() {
		// error||success -> cleared
		if(self.state == null || (self.state[:state] != StateRequestSuccess && self.state[:state] != StateRequestError)) {
			return false;
		}
		Logger.getInstance().info("ref=nest-api at=clear-state");
		self.state = null;
		self.notifyResults();
		return true;
	}

	protected function setStateRequesting(text) {
		// clear||complete -> requesting
		if (self.state != null && self.state[:state] == StateRequesting) {
			return false;
		}
		self.state = { :state => StateRequesting, :text => text };
		self.notifyResults();
		return true;
	}

	protected function setStateRequestError(text) {
		// requesting -> error
		if(self.state == null || self.state[:state] != StateRequesting) {
			return false;
		}
		self.state = { :state => StateRequestError, :text => text };
		self.notifyResults();
		return true;
	}

	protected function setStateRequestSuccess() {
		// requesting -> success
		if(self.state == null || self.state[:state] != StateRequesting) {
			return false;
		}		
		self.state = { :state => StateRequestSuccess };
		self.notifyResults();
		return true;
	}

	function clearPollerState() {
		// error||success -> cleared
		if(self.pollerState == null || (self.pollerState[:state] != StateRequestSuccess && self.pollerState[:state] != StateRequestError)) {
			return false;
		}
		self.pollerState = null;
		self.notifyResults();
		return true;
	}

	protected function setPollerStateRequesting() {
		// clear||complete -> requesting
		if (self.pollerState != null && self.pollerState[:state] == StateRequesting) {
			return false;
		}
		self.pollerState = { :state => StateRequesting };
		self.notifyResults();
		return true;
	}

	protected function setPollerStateRequestError(text) {
		// requesting -> error
		if(self.pollerState == null || self.pollerState[:state] != StateRequesting) {
			return false;
		}
		self.pollerState = { :state => StateRequestError, :text => text };
		self.notifyResults();
		return true;
	}

	protected function setPollerStateRequestSuccess() {
		// requesting -> success
		if(self.pollerState == null || self.pollerState[:state] != StateRequesting) {
			return false;
		}		
		self.pollerState = { :state => StateRequestSuccess };
		self.notifyResults();
		return true;
	}
	
	protected function isPhoneConnected() {
		return System.getDeviceSettings().phoneConnected; 
	}

    function requestCameraStatus() {
    	var now = Time.now();
    	var accessToken = Properties.getNestAccessToken();
    	var phoneConnected = self.isPhoneConnected();
    	// our poller runs every 30 seconds, so make sure we're rate limitting user-initiated requests to 1 per second max
    	if (!phoneConnected || accessToken == null || (self.camerasUpdatedAt != null && now.lessThan(self.camerasUpdatedAt.add(Gregorian.duration({:seconds => 1}))))) {
    		Logger.getInstance().infoF(
    			"ref=nest-api at=skip-request-camera-status has-token=$1$ cameras-updated-delta=$2$ phone-connected=$3$",
    			[accessToken != null, (self.camerasUpdatedAt == null ? "null" : now.value()-self.camerasUpdatedAt.value()), phoneConnected]
    		);
    		return;
    	} else if(!self.setPollerStateRequesting()) {
			return;
		}
		Logger.getInstance().info("ref=nest-api at=request-camera-status");	
        Comm.makeWebRequest(
        	Lang.format("$1$/api/v1/devices", [Env.NestApiProxyURI]),
            null,
            {
            	:method => Comm.HTTP_REQUEST_METHOD_GET,
            	:headers => {
            		"Authorization" => Lang.format("Bearer $1$", [accessToken])
            	}
            },
        	self.method(:onCameraListResponse)
    	);
    }
    
    function onCameraListResponse(responseCode, data) {    	
    	if (responseCode != 200) {
    		Logger.getInstance().infoF("ref=nest-api at=on-camera-list-response response-code='$1$'", [responseCode]);
    		if (responseCode == 401 || responseCode == 403) {
	    		self.setPollerStateRequestError("Auth Error!");
    			Properties.clearAll();    			
    		} else {
	    		self.setPollerStateRequestError(Lang.format("Error $1$", [responseCode]));
    		}
    	} else if (self.setPollerStateRequestSuccess()) {
    		var cameraList = data;
    		// clean out some of the data we don't use since the memory usage may be too beefy
    		for (var i = 0; i < cameraList.size(); i++) {
    			for (var j = 0; j < unusedCameraFields.size(); j++) {
    				cameraList[i].remove(unusedCameraFields[j]);
    			} 
    		}
    		Logger.getInstance().infoF("ref=nest-api at=on-camera-list-response response-code='$1$' data='$2$'", [responseCode, cameraList]);
    		self.cameraList = cameraList;
    		self.camerasUpdatedAt = Time.now();
    	}
    }
    
    function requestToggleStreaming(camera) {
    	var accessToken = Properties.getNestAccessToken();
    	if (accessToken == null) {
    		return;
    	}
    	var nextOnState = camera["is_on"] ? "off" : "on";
		if(!self.setStateRequesting("Powering " + nextOnState + "...")) {
			return;
		}
		if(camera["status"] != 1) {
    		self.setStateRequestError(Lang.format("$1$ disconnected.\nConnect before power $2$.", [camera["alias"], nextOnState]));
    		return;
    	}
    	Logger.getInstance().infoF("ref=nest-api at=request-toggle-streaming camera=$1$ to=$2$", [camera["deviceId"], !camera["is_on"]]);
    	self.temp = camera;  	
        Comm.makeWebRequest(
            Lang.format("$1$/api/v1/devices/$2$", [Env.NestApiProxyURI, camera["deviceId"]]),
            { "is_on" => !camera["is_on"] },
            {
            	:method => Comm.HTTP_REQUEST_METHOD_PUT,
            	:headers => {
            		"Authorization" => Lang.format("Bearer $1$", [accessToken]),
            		"Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON
            	},
            	:responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
        	self.method(:onCameraEnableStreamingResponse)
    	);    
    }

    function onCameraEnableStreamingResponse(responseCode, data) {
    	Logger.getInstance().infoF("ref=nest-api at=on-camera-enable-streaming-response response-code='$1$' data='$2$'", [responseCode, data]);
    	if (responseCode != 200) {
    		self.setStateRequestError(Lang.format("Failed to update camera:\nCode $1$.", [responseCode]));
    	} else {
    		self.temp["is_on"] = !self.temp["is_on"];
    		self.temp = null;
    		self.setStateRequestSuccess();
    		// self.requestCameraStatus(); // state may be replicating still
    	}
    }

    function getCameraList() {
    	return self.cameraList;
    }
    
    function hasCameras() {
    	return self.cameraList != null && self.cameraList.size() > 0;
    }
    
    function getCamerasUpdatedAt() {
    	return self.camerasUpdatedAt;
    }
    
    function isConnected() {
    	return Properties.connectedToNest();
    }

    function startTimer() {
    	if (Cron.getInstance().isEnabled(pollerTimerName)) {
    		return;
    	}
    	
    	Logger.getInstance().info("ref=nest-api at=start-timer");
		self.loadCachedCameraList();
		self.requestCameraStatus();
		Cron.getInstance().register(pollerTimerName, 30000, self.method(:requestCameraStatus), true);
    }
    
    function stopTimer() {
    	if (!Cron.getInstance().isRegistered(pollerTimerName)) {
    		return;
    	}

		Logger.getInstance().info("ref=nest-api at=stop-timer");
		self.saveCachedCameraList();
    	Comm.cancelAllRequests();
    }
    
    protected function loadCachedCameraList() {
    	if (self.cameraList != null) {
    		return;
    	}
		self.cameraList = Properties.getCameraList();
		self.camerasUpdatedAt = Properties.getCamerasUpdatedAt();
    }

    protected function saveCachedCameraList() {
    	var previousSaveTime = Properties.getCamerasUpdatedAt();
    	if (self.cameraList == null || self.camerasUpdatedAt == null || (previousSaveTime != null && !self.camerasUpdatedAt.greaterThan(previousSaveTime))) {
    		return;
    	}
    	Properties.setCameraList(self.cameraList);
    	Properties.setCamerasUpdatedAt(self.camerasUpdatedAt);
    }
    
    // oauth flow based on https://github.com/garmin/connectiq-apps/blob/1a7588e4c85726518c6744213516c9988ebdf45e/apps/strava-api/source/StravaLogin.mc
    function requestOauthConnect() {
    	if (self.connecting) {
    		return;
    	} else if(!self.setStateRequesting("Connecting, check phone...")) {
			return;
		}
    	Logger.getInstance().info("ref=nest-api at=request-oauth-connect");
    	self.connecting = true;
    	Comm.makeOAuthRequest(
    		Lang.format("$1$/oauth2/authorize", [Env.NestApiProxyURI]),
    		{
	    		"redirect_uri" => "https://localhost",
	    		"response_type" => "code",
	    		"client_id" => Env.NestClientId,
	    		"state" => "TODO"
	    	},
    		"https://localhost",
    		Comm.OAUTH_RESULT_TYPE_URL,
    		// params in redirect, mapped to keys in response dictionary
    		{"code" => "code", "error" => "error", "state" => "state"}
    	);

    	// start our timer to cancel the request after some time
    	Cron.getInstance().register(cancelOauthTimerName, 45000, self.method(:cancelOauthConnect), false);
    }
    
    // https://forums.garmin.com/forum/developers/connect-iq/1270860-detect-if-user-cancelled-oauth-dialog-communications-makeoauthrequest?view=stream
    function cancelOauthConnect() {
    	if (!self.connecting) {
    		return;
    	}
    	Logger.getInstance().info("ref=nest-api at=cancel-oauth-connect");
		if(!self.setStateRequestError("Oauth connect timed out.\nPlease retry.")) {
			return;
		}
		self.connecting = false;
    }

    // resp.responseCode non-http statuses documented in
    // https://developer.garmin.com/downloads/connect-iq/monkey-c/doc/Toybox/Communications.html
    function onOauthResponsePhase1(resp) {    	
    	if (!self.connecting) {
    		return;
    	}
    	Logger.getInstance().infoF("ref=nest-api at=on-oauth-response-phase-1 response-code='$1$'", [resp.responseCode]);
    	if (resp.data != null && resp.data["code"] != null && "TODO".equals(resp.data["state"])) {
    		// skip setting request success to avoid transaction race between toast and phase 2 response
			//if(!self.setStateRequestSuccess()) {
			//	return;
			//}
    		self.requestAccessToken(resp.data["code"]);
    	} else {
			if(!self.setStateRequestError(Lang.format("Failed to authorize:\nCode $1$.", [resp.responseCode]))) {
				return;
			}
    		self.connecting = false;
    	}
    }

    function requestAccessToken(code) {
    	if (!self.connecting) {
    		return;
    	}
    	// already "requesting"
		//if(!self.setStateRequesting(null)) {
		//	return;
		//}
    	Logger.getInstance().infoF("ref=nest-api at=request-access-token code='$1$'", [code]);
        Comm.makeWebRequest(
        	Lang.format("$1$/oauth2/token", [Env.NestApiProxyURI]),
            {
            	"grant_type" => "authorization_code",
            	"redirect_uri" => "https://localhost",
            	"client_secret" => Env.NestClientSecret,
            	"client_id" => Env.NestClientId,
            	"code" => code
            },
            {
            	:method => Comm.HTTP_REQUEST_METHOD_POST
            },
        	self.method(:onOauthResponsePhase2)
    	);
    }

    function onOauthResponsePhase2(responseCode, data) {
    	Logger.getInstance().infoF("ref=nest-api at=on-oauth-response-phase-2 response-code='$1$' data='$2$'", [responseCode, data]);
    	Cron.getInstance().unregister(cancelOauthTimerName);
        self.connecting = false;
        if(data != null && responseCode == 200) {
			if(!self.setStateRequestSuccess()) {
				return;
			}
        	// TODO need to worry about if this gets revoked or needs a refresh for v2
		    Properties.setNestAccessToken(data["access_token"]);
		    self.requestCameraStatus();
        } else {
        	self.setStateRequestError(Lang.format("Failed to generate token:\nCode $1$.", [responseCode]));
        }
    }
}
		
// vi:syntax=javascript filetype=javascript