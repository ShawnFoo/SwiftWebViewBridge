;(function() {
	if (window.SwiftWebViewBridge) {
		return;
	}
	var hiddenMessagingIframe;
	var unsentMessageQueue = [];
	var startupRCVDMessageQueue = [];
	var messageHandlers = {};
	
	var CUSTOM_PROTOCOL_SCHEME = 'swvbscheme';
	var CUSTOM_PROTOCOL_HOST = '__SWVB_Host_MESSAGE__';
	var TRIGGER_SOURCE = CUSTOM_PROTOCOL_SCHEME + '://' + CUSTOM_PROTOCOL_HOST;
	
	var responseCallbacks = {};
	var uniqueId = 1;
	
    // create an iframe to trigger Swift entrance method(..shouldStartLoadWithRequest..) by setting the src
	function createHiddenIframe() {
		hiddenMessagingIframe = document.createElement('iframe');
		hiddenMessagingIframe.style.display = 'none';
		hiddenMessagingIframe.src = TRIGGER_SOURCE;
		document.documentElement.appendChild(hiddenMessagingIframe);
	}

	function helloSwift() {
		hiddenMessagingIframe.src = TRIGGER_SOURCE;
	}

	function init(defaultHandler) {
		if (SwiftWebViewBridge._defaultHandler) { 
			throw new Error('SwiftWebViewBridge.init called twice');
		}
		SwiftWebViewBridge._defaultHandler = defaultHandler;

		// handle msgs received before bridge init.(Swift starts sending msgs when all urls did load, inclued failed loadings)
		var receivedMessages = startupRCVDMessageQueue;
		startupRCVDMessageQueue = null;
		for (var i = 0; i < receivedMessages.length; i++) {
			dispatchMessageFromSwift(receivedMessages[i]);
		}
	}

	// Method For Swift Calling
	
	// Swift fetch messages by calling this method
	function _fetchJSMessage() {
		var messageQueueString = JSON.stringify(unsentMessageQueue);
		unsentMessageQueue = [];
		return messageQueueString;
	}

	// Swift send message to this entrance
	function _handleMessageFromSwift(jsonMsg) {
		if (startupRCVDMessageQueue) {
			startupRCVDMessageQueue.push(jsonMsg);
		} 
		else {
			dispatchMessageFromSwift(jsonMsg);
		}
	}

	// Interaction Between Swift & JS

	function sendDataToSwift(data, responseCallback) {
		callSwiftHandler(null, data, responseCallback);
	}
  
    function callSwiftHandler(handlerName, data, responseCallback) {
		var message = handlerName ? {handlerName: handlerName, data: data} : {data: data};
        if (responseCallback) {
            var callbackId = 'cb_'+(uniqueId++)+'_JS_'+new Date().getTime();
            responseCallbacks[callbackId] = responseCallback;
            message['callbackId'] = callbackId;
		}
		unsentMessageQueue.push(message);
		helloSwift();
    }

    function triggerSwiftCallback(message) {
    	unsentMessageQueue.push(message);
    	helloSwift();
    }

	function registerHandlerForSwift(handlerName, handler) {
		messageHandlers[handlerName] = handler;
	}

	// Message Dispatch
	function dispatchMessageFromSwift(jsonMsg) {
		window.setTimeout(function timeoutDispatchMessageFromSwift() {
			var message = JSON.parse(jsonMsg);
			var responseCallback;
			// JS callback(after Swift finished designated handler called by JS)
			if (message.responseId) {
				responseCallback = responseCallbacks[message.responseId];
				if (responseCallback) {
					responseCallback(message.responseData);
					delete responseCallbacks[message.responseId];
				}
			} 
			else {// Swift call JS handler
				if (message.callbackId) {
					// if there is callbackId(that means Swift has a callback), 
					// JS send it back as responseId to Swift so that Swift can find and execute callback 
					var callbackResponseId = message.callbackId;
					responseCallback = function(responseData) {	
						triggerSwiftCallback({
							responseId: callbackResponseId, 
							responseData: responseData 
						});
					};
				}
				
				var handler = SwiftWebViewBridge._defaultHandler;
				if (message.handlerName) {
					handler = messageHandlers[message.handlerName];
				}
			
				if (handler) {
					try {
						handler(message.data, responseCallback);
					} 
					catch(exception) {
						if (typeof console != 'undefined') {
							console.log('SwiftWebViewBridge: WARNING: javascript handler threw.', message, exception);
						}
					}
				}
				else {
					onerror('No defaultHandler!');
				}
			}
		});
	}

	// create global bridge object
	window.SwiftWebViewBridge = {
		init: init,
		sendDataToSwift: sendDataToSwift,
		registerHandlerForSwift: registerHandlerForSwift,
		callSwiftHandler: callSwiftHandler,
		_fetchJSMessage: _fetchJSMessage,
		_handleMessageFromSwift: _handleMessageFromSwift
	};

	createHiddenIframe();
	// dispatch event for the listener
    var readyEvent = document.createEvent('Events');
	readyEvent.initEvent('SwiftWebViewBridgeReady');
	document.dispatchEvent(readyEvent);
})();
