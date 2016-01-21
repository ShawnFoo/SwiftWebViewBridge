//
//  SwiftJavaScriptBridge.swift
//  SwiftJavaScriptBridge
//
//  Created by ShawnFoo on 16/1/18.
//  Copyright © 2016年 ShawnFoo. All rights reserved.
//

import UIKit

public typealias WVJBResponseCallBack = AnyObject -> Void
public typealias WVJBHandler = (AnyObject, WVJBResponseCallBack) -> Void
public typealias WVJBHandlerDic = [String: WVJBHandler]
public typealias WVJBCallbackDic = [String: WVJBResponseCallBack]
public typealias WVJBMessage = [String: AnyObject]

public class SwiftJavaScriptBridge: NSObject, UIWebViewDelegate {
    
    // MARK: - Constants
    
    private var kCustomProtocolScheme: String {
        return "WVJBScheme"
    }
    
    private var kCustomProtocolHost: String {
        return "__WVJB_Host_MESSAGE__"
    }
    
    private var kJsCheckObjectDefinedCommand: String {
        return "typeof WebViewJavascriptBridge == \'object\';"
    }
    
    private var kJsFetchMethodCallsCommand: String {
        return "WebViewJavascriptBridge._fetchJSMessage();"
    }
    
    // MARK: - Proporties
    
    private weak var webView: UIWebView?
    private weak var originalDelegate: AnyObject?
    private var numOfLoadingRequests = 0
    
    private var javascript: String?
    // identity of the response callback
    private var uniqueId = 1
    // the queue stored messages called or sent before webView did finish load(js injection also finished in that function)
    private lazy var startupMessageQueue: [WVJBMessage]? = {
        return [WVJBMessage]()
    }()
    private var defaultHandler: WVJBHandler? {
        get {
            return messageHandlers["__kDefaultHandler__"]
        }
        set {
            if let handler = newValue {
                
                messageHandlers["__kDefaultHandler__"] = handler
            }
        }
    }
    // save the JS callback in the Swift side, only pass the uniqueId to JS for the callback
    private lazy var jsCallbacks: WVJBCallbackDic = WVJBCallbackDic()
    // handlers for JS calling
    private lazy var messageHandlers: WVJBHandlerDic = WVJBHandlerDic()
    
    // MARK: - Factory / Initilizers
    
    public class func bridge(webView: UIWebView, defaultHandler handler: WVJBHandler?) -> SwiftJavaScriptBridge? {
        
        var js: String?
        
        // load js
        guard let filePath = NSBundle.mainBundle().pathForResource("WebViewJavascriptBridge", ofType: "js") else {
            
            print("Couldn't find WebViewJavascriptBridge.js file in bundle, please check again")
            return nil
        }
        
        do {
            
            js = try NSString.init(contentsOfFile: filePath, encoding: NSUTF8StringEncoding) as String
        }
        catch let error as NSError {
            print("Error when loading js file: \(error)")
            
            return nil
        }
        
        let bridge = SwiftJavaScriptBridge.init()
        
        bridge.javascript = js
        bridge.webView = webView;
        // keep ref to original delegate
        bridge.originalDelegate = webView.delegate
        // replace it
        bridge.webView!.delegate = bridge
        bridge.defaultHandler = handler
        
        return bridge
    }

    private override init() {
        super.init()
    }
    
    private convenience init(webView: UIWebView, javascript: String) {
        self.init()
        
        self.webView = webView
        self.javascript = javascript
    }
    
    // MARK: - WebViewDelegate
    
    // It's the only entrance where JavaScript can call Swift/ObjC handler or callback.Every URL loading in any frames will trigger this method
    public func webView(webView: UIWebView, shouldStartLoadWithRequest request: NSURLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        
        if let webview:UIWebView = webView, url:NSURL = request.URL {

            if isSchemeCorrect(url) && isHostCorrect(url) {
                // after JS trigger this method by loading URL, Swift needs to ask JS for commands
                if let jsonCmds = webview.stringByEvaluatingJavaScriptFromString(kJsFetchMethodCallsCommand) {
                    handleMessagesFromJS(jsonCmds)
                }
            }
            else if let strongDelegate = originalDelegate as? UIWebViewDelegate {
                
                if let sholudLoad = strongDelegate.webView?(webView, shouldStartLoadWithRequest: request, navigationType: navigationType) {

                    return sholudLoad
                }
            }
            else {
                return true
            }
        }
        
        return false
    }
    
    public func webViewDidStartLoad(webView: UIWebView) {

        numOfLoadingRequests++
        if let strongDelegate = originalDelegate as? UIWebViewDelegate {
            strongDelegate.webViewDidStartLoad?(webView)
        }
    }
    
    public func webViewDidFinishLoad(webView: UIWebView) {
        
        numOfLoadingRequests--
        // after all frames have loaded, starting to inject js and dispatch unhanlded message
        if numOfLoadingRequests == 0 &&
            "false" == webView.stringByEvaluatingJavaScriptFromString(kJsCheckObjectDefinedCommand)
        {// make sure the js has not been injected or no duplicated WebViewJavascriptBridge js object
            
            if let injectedJS = javascript {
                
                webView.stringByEvaluatingJavaScriptFromString(injectedJS)
                dispatchStartupMessageQueue()
            }
        }
    }
    
    public func webView(webView: UIWebView, didFailLoadWithError error: NSError?) {
        
        numOfLoadingRequests--
        if let strongDelegate = originalDelegate as? UIWebViewDelegate {
            strongDelegate.webView?(webView, didFailLoadWithError: error)
        }
    }
    
    // MARK: - URL Checking
    
    private func isSchemeCorrect(url: NSURL) -> Bool {
        
        return url.scheme == self.kCustomProtocolScheme;
    }
    
    private func isHostCorrect(url: NSURL) -> Bool {
        
        return url.host == self.kCustomProtocolHost;
    }
    
    // MARK: - Message Manage
    
    // MARK: Message Sent To JS
    
    /**
    Add message that will be sent to JS to Queue
    
    - parameter msg: message that will be sent to JS
    */
    private func addToMessageQueue(msg: WVJBMessage) {
        
        if nil != startupMessageQueue {
            startupMessageQueue?.append(msg)
        }
        else {
            dispatchMessage(msg)
        }
    }
    
    /**
     sending every message(send data or call handler) that happened before UIWebView did finish all loadings to JS one by one
     */
    private func dispatchStartupMessageQueue() {

        if let queue = startupMessageQueue {
            for message in queue {
                dispatchMessage(message)
            }
            startupMessageQueue = nil
        }
    }
    
    /**
    Send message to JS. (Swift/ObjC call JS Handlers here)
    
    - parameter msg: message that will be sent to JS
    */
    private func dispatchMessage(msg: WVJBMessage) {

        if let jsonMsg: JSON = JSON(msg) {
            
            let jsCommand = "WebViewJavascriptBridge._handleMessageFromSwift(\(jsonMsg))"
            if NSThread.isMainThread() {
                webView?.stringByEvaluatingJavaScriptFromString(jsCommand)
            }
            else {
                dispatch_sync(dispatch_get_main_queue()) {
                    self.webView?.stringByEvaluatingJavaScriptFromString(jsCommand)
                }
            }
        }
    }
    
    // MARK: Messages Sent From JS
    private func handleMessagesFromJS(jsonCmds: String) {

        guard let msgs = JSON(jsonCmds).array else {
            print("Error!Invalid Received From JS: \(jsonCmds)")
            return
        }
        
        for msgJSON in msgs {
            
            if let msgDic = msgJSON.dictionaryObject {
                
                // Swift callback(after JS finished designated handler called by Swift)
                if let responseId = msgDic["responseId"] as? String {

                    if let callback = jsCallbacks[responseId] {
                        
                        let responseData = msgDic["responseData"] != nil ? msgDic["responseData"] : NSNull()
                        
                        callback(responseData!)
                        jsCallbacks.removeValueForKey(responseId)
                    }
                    else {
                        print("No matching callback closure for: \(msgDic)")
                    }
                }
                else { // JS call Swift Handler
                    
                    let callback:WVJBResponseCallBack = {
                        // if there is callbackId(that means JS has a callback), Swift send it back as responseId to JS so that JS can find and execute callback
                        if let callbackId: String = msgDic["callbackId"] as? String {

                            return { [unowned self] (responseData: AnyObject?) -> Void in
                                
                                let data = responseData != nil ? responseData! : NSNull()
                                
                                let msg: WVJBMessage = ["responseId": callbackId, "responseData": data]
                                self.addToMessageQueue(msg)
                            }
                        }
                        else {
                            return { (data: AnyObject?) -> Void in
                            // emtpy closure, make sure this is non-optional
                            }
                        }
                    }()
                    
                    let handler:WVJBHandler? = { [unowned self] in

                        if let handlerName = msgDic["handlerName"] as? String {
                            
                            return self.messageHandlers[handlerName]
                        }
                        
                        return self.defaultHandler
                    }()
                    
                    guard let handlerClosure = handler else {
                        fatalError("No handler for msg from JS: \(msgDic)..Please create a default handler when initialize the bridge at least = )")
                    }
                    
                    let msgData = msgDic["data"] != nil ? msgDic["data"] : NSNull()
                        
                    handlerClosure(msgData!, callback)
                }
            }
            else {
                print("JSON Object Deserilization Failed!")
            }
        }
    }
    
    // MARK: - Interaction Between Swift/ObjC And JS
    
    // MARK: Swift Send Message To JS
    
    public func sendDataToJS(data: AnyObject) {
        callJSHandler(nil, params: data, responseCallback: nil)
    }
    
    public func sendDataToJS(data: AnyObject, responseCallback: WVJBResponseCallBack?) {
        callJSHandler(nil, params: data, responseCallback: responseCallback)
    }
    
    /**
     Call JavaScript handler
     
     - parameter handlerName:      handlerName should be identical to handler registered in JS
     - parameter params:           params(optional)
     - parameter responseCallback: callback(optional) will execute, after JS finished the matching handler
     */
    public func callJSHandler(handlerName: String?, params: AnyObject?, responseCallback: WVJBResponseCallBack?) {
        
        var message = WVJBMessage()
        
        message["data"] = params != nil ? params : NSNull()
        
        if let name = handlerName {
            message["handlerName"] = name
        }
        
        if let callback = responseCallback {
            // pass this Id to JS, and then after JS finish its handler, this Id will pass back to Swift as responseId, so Swift can use it to find and execute the matching callback
            let callbackId = "cb_\(uniqueId++)_Swift_\(NSDate())"
            jsCallbacks[callbackId] = callback
            message["callbackId"] = callbackId
        }
        
        addToMessageQueue(message)
    }
    
    // MARK: Rigister Handler For Message From JS
    
    /**
    Register a handler for JavaScript calling
    
    - parameter name:    handlerName
    - parameter handler: closure
    */
    public func registerHandlerForJS(handlerName name: String, handler:WVJBHandler) {
        
        messageHandlers[name] = handler
    }
}
