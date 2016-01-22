# SwiftWebViewBridge

Swift version of [WebViewJavascriptBridge](https://github.com/marcuswestin/WebViewJavascriptBridge) with more simplified, friendly methods to handle messages between Swift and JS in UIWebViews

---
##Requirements

1. Xcode7.0+
2. iOS7.0+
3. [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON)(The communication between Swift and JS depends on JSON messages.The SwiftyJSON.swift file includes in SwiftWebViewBridge document.If you have imported it by other ways, you could remove it.)

---
##How to use it:

###General

1. initialize a bridge with defaultHandler
2. register handlers to handle different events
3. send data / call handler on both sides

###For Swift

#####func bridge(webView: UIWebView, defaultHandler handler: SWVBHandler?) -> SwiftJavaScriptBridge?
Generate a bridge with associated webView and default handler to deal with messages from js without specifying designated handler

```
guard let bg = SwiftJavaScriptBridge.bridge(webView, defaultHandler: { data, responseCallback in
	print("Swift received message from JS: \(data)")
	responseCallback("Swift already got your msg, thanks")
}) else {        
  	print("Error: initlizing bridge failed")
  	return
}
```
#####func registerHandlerForJS(handlerName name: String, handler:SWVBHandler)
Register a handler for JavaScript calling

```
// take care of retain cycle!
bridge.registerHandlerForJS(handlerName: "getSesionId", handler: { [unowned self] data, responseCallback in
	let sid = self.session            
	responseCallback(["msg": "Swift has already finished its handler", "returnValue": [1, 2, 3]])
})
```
#####func sendDataToJS(data: AnyObject)
Simply Sent data to JS 

```
bridge.sendDataToJS(["msg": "Hello JavaScript", "gift": ["100CNY", "1000CNY", "10000CNY"]])
```
#####func sendDataToJS(data: AnyObject, responseCallback: SWVBResponseCallBack?)
Send data to JS with callback closure

```
bridge.sendDataToJS("Did you received my gift, JS?", responseCallback: { data in
	print("Receiving JS return gift: \(data)")
})
```
#####func callJSHandler(handlerName: String?, params: AnyObject?, responseCallback: SWVBResponseCallBack?)
Call JavaScript registered handler

```
bridge.callJSHandler("alertReceivedParmas", params: ["msg": "JS, are you there?"], responseCallback: nil)
```

#####two custom closures mentioned above 

```
/// 1st param: resonseData to JS
public typealias SWVBResponseCallBack = AnyObject -> Void
/// 1st param: data sent from JS; 2nd param: responseCallback for sending data back to JS
public typealias SWVBHandler = (AnyObject, SWVBResponseCallBack) -> Void
```

###For JavaScript

#####function init(defaultHandler)

```
bridge.init(function(message, responseCallback) {
	log('JS got a message', message)
	var data = { 'JS Responds' : 'Message received = )' }
	responseCallback(data)
})
```
#####function registerHandlerForSwift(handlerName, handler)

```
bridge.registerHandlerForSwift('alertReceivedParmas', function(data, responseCallback) {
	log('ObjC called alertPassinParmas with', JSON.stringify(data))
	alert(JSON.stringify(data))
	var responseData = { 'JS Responds' : 'alert triggered' }
	responseCallback(responseData)
})
```

#####function sendDataToSwift(data, responseCallback)

```
bridge.sendDataToSwift('Say Hello Swiftly to Swift')
bridge.sendDataToSwift('Hi, anybody there?', function(responseData){
	alert("got your response: " + JSON.stringify(responseData))
})
```

#####function callSwiftHandler(handlerName, data, responseCallback)

```
SwiftWebViewBridge.callSwiftHandler("printReceivedParmas", {"name": "小明", "age": "6", "school": "GDUT"}, function(responseData){
	log('JS got responds from Swift: ', responseData)
})
```