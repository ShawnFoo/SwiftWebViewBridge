//
//  SwiftWebViewBridge.swift
//  SwiftWebViewBridge
//
//  Created by ShawnFoo on 16/1/18.
//  Copyright © 2016年 ShawnFoo. All rights reserved.
//

import UIKit

//If you have installed SwiftJSON by Cocoapods, etc. You can uncomment the import below, also delete SwiftyJSON.swift file in SwiftWebViewBridge doc
//import SwiftJSON

private enum LogType: CustomStringConvertible {
    case ERROR(String), SENT(AnyObject), RCVD(AnyObject)
    
    var description: String {
        switch self {
        case let .ERROR(msg):
            return "LOGGING_ERROR: \(msg)"
        case let .SENT(msg):
            return "LOGGING_SENT: \(msg)"
        case let .RCVD(msg):
            return "LOGGING_RCVD: \(msg)"
        }
    }
}

public typealias SWVBResponseCallBack = AnyObject -> Void
public typealias SWVBHandler = (AnyObject, SWVBResponseCallBack) -> Void
public typealias SWVBHandlerDic = [String: SWVBHandler]
public typealias SWVBCallbackDic = [String: SWVBResponseCallBack]
public typealias SWVBMessage = [String: AnyObject]

public class SwiftJavaScriptBridge: NSObject, UIWebViewDelegate {
    
    // MARK: - Constants
    
    private var kCustomProtocolScheme: String {
        return "swvbscheme" //lowercase!
    }
    
    private var kCustomProtocolHost: String {
        return "__SWVB_Host_MESSAGE__"
    }
    
    private var kJsCheckObjectDefinedCommand: String {
        return "typeof SwiftWebViewBridge == \'object\';"
    }
    
    private var kJsFetchMessagesCommand: String {
        return "SwiftWebViewBridge._fetchJSMessage();"
    }
    
    // MARK: - Proporties
    
    public static var logging = true
    
    private weak var webView: UIWebView?
    private weak var originalDelegate: AnyObject?
    private var numOfLoadingRequests = 0
    
    private var javascript: String?
    // identity of the response callback
    private var uniqueId = 1
    // the queue stored messages called or sent before webView did finish load(js injection also finished in that function)
    private lazy var startupMessageQueue: [SWVBMessage]? = {
        return [SWVBMessage]()
    }()
    private var defaultHandler: SWVBHandler? {
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
    private lazy var jsCallbacks: SWVBCallbackDic = SWVBCallbackDic()
    // handlers for JS calling
    private lazy var messageHandlers: SWVBHandlerDic = SWVBHandlerDic()
    
    // MARK: - Factory / Initilizers
    
    public class func bridge(webView: UIWebView, defaultHandler handler: SWVBHandler?) -> SwiftJavaScriptBridge? {
        
        // load js
        guard let filePath = NSBundle.mainBundle().pathForResource("SwiftWebViewBridge", ofType: "js") else {
            print("Error: Couldn't find SwiftWebViewBridge.js file in bundle, please check again")
            return nil
        }
        
        var js: String?
        do {
            js = try NSString.init(contentsOfFile: filePath, encoding: NSUTF8StringEncoding) as String
        }
        catch let error as NSError {
            print("Error: Couldn't load js file: \(error)")
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
    
    // MARK: - WebViewDelegate Methods
    
    // It's the only entrance where JavaScript can call Swift/ObjC handler or callback.Every URL loading in any frames will trigger this method
    public func webView(webView: UIWebView, shouldStartLoadWithRequest request: NSURLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        
        if let url:NSURL = request.URL {

            if isSchemeCorrect(url) && isHostCorrect(url) {
                // after JS trigger this method by loading URL, Swift needs to ask JS for messages by itself
                if let jsonMessages = webView.stringByEvaluatingJavaScriptFromString(kJsFetchMessagesCommand) {
                    
                    handleMessagesFromJS(jsonMessages)
                }
                else {
                    print("Didn't fetch any message from JS!")
                }
            }
            else if let strongDelegate = originalDelegate as? UIWebViewDelegate {
                
                if let sholudLoad = strongDelegate.webView?(webView, shouldStartLoadWithRequest: request, navigationType: navigationType) {

                    return sholudLoad
                }
            }
            
            return true
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
        {// make sure the js has not been injected or no duplicated SwiftWebViewBridge js object
            
            if let injectedJS = javascript {
                
                webView.stringByEvaluatingJavaScriptFromString(injectedJS)
                
                if webView.stringByEvaluatingJavaScriptFromString(kJsCheckObjectDefinedCommand) != "true" {
                    print("Injection of js Failed!")
                }
                else {
                    dispatchStartupMessageQueue()
                }
            }
            else {
                print("Didn't load the js file!")
            }
        }
        
        if let strongDelegate = originalDelegate as? UIWebViewDelegate {
            strongDelegate.webViewDidFinishLoad?(webView)
        }
    }
    
    public func webView(webView: UIWebView, didFailLoadWithError error: NSError?) {
        
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
    private func addToMessageQueue(msg: SWVBMessage) {
        
        print(msg)
        
        if nil != startupMessageQueue {
            startupMessageQueue!.append(msg)
        }
        else {
            dispatchMessage(msg)
        }
    }
    
    /**
     Sending every message(send data or call handler) that happened before UIWebView did finish all loadings to JS one by one
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
    private func dispatchMessage(msg: SWVBMessage) {

        if let jsonMsg: String = javascriptStylizedJSON(msg) {
            
            swvb_printLog(.SENT(jsonMsg))
            let jsCommand = "SwiftWebViewBridge._handleMessageFromSwift('\(jsonMsg)')"
            if NSThread.isMainThread() {
                webView?.stringByEvaluatingJavaScriptFromString(jsCommand)
            }
            else {
                dispatch_sync(dispatch_get_main_queue()) {
                    self.webView?.stringByEvaluatingJavaScriptFromString(jsCommand)
                }
            }
        }
        else {
            swvb_printLog(.ERROR("Swift Object Serialization Failed: \(msg)"))
        }
    }
    
    // MARK: Messages Sent From JS
    private func handleMessagesFromJS(jsonMessages: String) {
        
        guard let jsonObj:JSON = JSON.parse(jsonMessages), msgs = jsonObj.array else
        {
            swvb_printLog(.ERROR("Deserilizing Received Msg From JS: \(jsonMessages)"))
            return
        }
        
        for msgJSON in msgs {
            
            if let msgDic = msgJSON.dictionaryObject {
                
                swvb_printLog(.RCVD(msgDic))
                
                // Swift callback(after JS finished designated handler called by Swift)
                if let responseId = msgDic["responseId"] as? String {

                    if let callback = jsCallbacks[responseId] {
                        
                        let responseData = msgDic["responseData"] != nil ? msgDic["responseData"] : NSNull()
                        
                        callback(responseData!)
                        jsCallbacks.removeValueForKey(responseId)
                    }
                    else {
                        swvb_printLog(.ERROR("No matching callback closure for: \(msgDic)"))
                    }
                }
                else { // JS call Swift Handler
                    
                    let callback:SWVBResponseCallBack = {
                        // if there is callbackId(that means JS has a callback), Swift send it back as responseId to JS so that JS can find and execute callback
                        if let callbackId: String = msgDic["callbackId"] as? String {

                            return { [unowned self] (responseData: AnyObject?) -> Void in
                                
                                let data:AnyObject = responseData != nil ? responseData! : NSNull()
                                
                                let msg: SWVBMessage = ["responseId": callbackId, "responseData": data]//
                                self.addToMessageQueue(msg)
                            }
                        }
                        else {
                            return { (data: AnyObject?) -> Void in
                            // emtpy closure, make sure callback closure param is non-optional
                            }
                        }
                    }()
                    
                    let handler:SWVBHandler? = { [unowned self] in

                        if let handlerName = msgDic["handlerName"] as? String {
                            
                            return self.messageHandlers[handlerName]
                        }
                        
                        return self.defaultHandler
                    }()
                    
                    guard let handlerClosure = handler else {
                        fatalError("No handler for msg from JS: \(msgDic)..Please at least create a default handler when initializing the bridge = )")
                    }
                    
                    let msgData = msgDic["data"] != nil ? msgDic["data"] : NSNull()
                        
                    handlerClosure(msgData!, callback)
                }
            }
            else {
                swvb_printLog(.ERROR("JSON Object Deserilization Failed!"))
            }
        }
    }
    
    // MARK: - Interaction Between Swift/ObjC And JS
    
    // MARK: Swift Send Message To JS
    
    /**
    Sent data to JS simply
    */
    public func sendDataToJS(data: AnyObject) {
        callJSHandler(nil, params: data, responseCallback: nil)
    }
    
    /**
     Send data to JS with callback closure
     */
    public func sendDataToJS(data: AnyObject, responseCallback: SWVBResponseCallBack?) {
        callJSHandler(nil, params: data, responseCallback: responseCallback)
    }
    
    /**
     Call JavaScript handler
     
     - parameter handlerName:      handlerName should be identical to handler registered in JS. If this param is nil or no-matching name in JS, its params will be sent to JS defaultHandler
     - parameter params:           params(optional)
     - parameter responseCallback: callback(optional) will execute, after JS finished the matching handler
     */
    public func callJSHandler(handlerName: String?, params: AnyObject?, responseCallback: SWVBResponseCallBack?) {
        
        var message = SWVBMessage()
        
        message["data"] = params != nil ? params : NSNull()
        
        if let name = handlerName {
            message["handlerName"] = name
        }
        
        if let callback = responseCallback {
            // pass this Id to JS, and then after JS finish its handler, this Id will pass back to Swift as responseId, so Swift can use it to find and execute the matching callback
            let callbackId = "cb_\(uniqueId++)_Swift_\(NSDate().timeIntervalSince1970)"
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
    public func registerHandlerForJS(handlerName name: String, handler:SWVBHandler) {
        
        messageHandlers[name] = handler
    }
    
    // MARK: - Print Log
    
    private func swvb_printLog(logType: LogType) {
        
        if SwiftJavaScriptBridge.logging {
            print(logType.description)
        }
    }
    
    // MARK: - JSON Serilization
    
    private func javascriptStylizedJSON(message: AnyObject) -> String? {
        
        if let jsonMsg: String = JSON(message).rawString(options: NSJSONWritingOptions()) {
            
            var jsonStr = jsonMsg.stringByReplacingOccurrencesOfString("\\", withString: "\\\\")
            jsonStr = jsonStr.stringByReplacingOccurrencesOfString("\"", withString: "\\\"")
            jsonStr = jsonStr.stringByReplacingOccurrencesOfString("\'", withString: "\\\'")
            jsonStr = jsonStr.stringByReplacingOccurrencesOfString("\n", withString: "\\n")
            jsonStr = jsonStr.stringByReplacingOccurrencesOfString("\r", withString: "\\r")
            jsonStr = jsonStr.stringByReplacingOccurrencesOfString("\t", withString: "\\t")
            jsonStr = jsonStr.stringByReplacingOccurrencesOfString("\u{2028}", withString: "\\u2028")// Line Seperator
            jsonStr = jsonStr.stringByReplacingOccurrencesOfString("\u{2029}", withString: "\\u2029")// Paragraph Seperator
            
            return jsonStr
        }
        
        return nil
    }
}
