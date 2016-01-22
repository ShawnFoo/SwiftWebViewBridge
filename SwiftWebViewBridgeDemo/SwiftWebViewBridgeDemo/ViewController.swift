//
//  ViewController.swift
//  SwiftWebViewBridgeDemo
//
//  Created by ShawnFoo on 16/1/20.
//  Copyright © 2016年 ShawnFoo. All rights reserved.
//

import UIKit

class ViewController: UIViewController, UIWebViewDelegate {
    
    // already set delegate to current ViewController in storyboard
    @IBOutlet weak var webView: UIWebView!
    
    @IBOutlet weak var webviewTitleLb: UILabel!
    @IBOutlet weak var loadingActivity: UIActivityIndicatorView!
    
    @IBOutlet weak var sendDataToJSBt: UIButton!
    
    @IBOutlet weak var sendDataToJSWithCallBackBt: UIButton!
    
    @IBOutlet weak var callJSHandlerBt: UIButton!
    
    @IBOutlet weak var callJSHandlerWithCallBackBt: UIButton!
    
    @IBOutlet weak var reloadBtItem: UIBarButtonItem!
    
    private var numOfLoadingRequest = 0
    
    private var bridge: SwiftJavaScriptBridge!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let bg = SwiftJavaScriptBridge.bridge(webView, defaultHandler: { data, responseCallback in
            
            print("Swift received message from JS: \(data)")
            
            // Actually, this responseCallback could be an empty closure when javascript has no callback, saving you from unwarping an optional parameter = )
            responseCallback("Swift already got your msg, thanks")
        }) else {
            
            print("Error: initlizing bridge failed")
            return
        }
        bridge = bg
//        SwiftJavaScriptBridge.logging = false
        
        bridge.registerHandlerForJS(handlerName: "printReceivedParmas", handler: { [unowned self] data, responseCallback in
            
            // if you used self in any bridge handler/callback closure, remember to declare weak or unowned self, preventing from retaining cycle!
            // Because VC owned bridge, brige owned this closure, and this cloure captured self!
            self.printReceivedParmas(data)
            
            responseCallback(["msg": "Swift has already finished its handler", "returnValue": [1, 2, 3]])
        })
        
        bridge.sendDataToJS(["msg": "Hello JavaScript", "gift": ["100CNY", "1000CNY", "10000CNY"]])
        
        loadLocalWebPage()
    }
    
    @IBAction func sendDataToJS(sender: AnyObject) {
        
        bridge.sendDataToJS(["msg": "Hello JavaScript", "gift": ["100CNY", "1000CNY", "10000CNY"]])
        
        /* same effect as above, as you can see in SwiftWebViewBridge implementation
        bridge?.callJSHandler(nil, params: ["msg": "Hello JavaScript", "gift": "100CNY"], responseCallback: nil)
        */
    }
    
    @IBAction func sendDataToJSWithCallback(sender: AnyObject) {
        
        bridge.sendDataToJS("Did you received my gift, JS?", responseCallback: { data in
        
            print("Receiving JS return gift: \(data)")
        })
    }
    
    @IBAction func callJSHandler(sender: AnyObject) {
        
        bridge.callJSHandler("alertReceivedParmas", params: ["msg": "JS, are you there?"], responseCallback: nil)
    }
    
    @IBAction func callJSHandlerWithCallback(sender: AnyObject) {
        
        bridge.callJSHandler("alertReceivedParmas", params: ["msg": "JS, I know you there!"]) { data in

            print("Got response from js: \(data)")
        }
    }
    
    func printReceivedParmas(data: AnyObject) {
        
        print("Swift recieved data passed from JS: \(data)")
    }
    
    func loadLocalWebPage() {
        
        guard let urlPath = NSBundle.mainBundle().URLForResource("Demo", withExtension: "html") else {
            
            print("Couldn't find the Demo.html file in bundle!")
            return
        }
        
        let request = NSURLRequest(URL: urlPath, cachePolicy: .ReloadIgnoringLocalCacheData, timeoutInterval: 10.0)
        webView.loadRequest(request)
    }

    @IBAction func reloadAction(sender: AnyObject) {
        
        numOfLoadingRequest = 0
        webviewTitleLb.text = ""
        loadingActivity.startAnimating()
        sendDataToJSBt.enabled = false
        sendDataToJSWithCallBackBt.enabled = false
        callJSHandlerBt.enabled = false
        callJSHandlerWithCallBackBt.enabled = false
        reloadBtItem.enabled = false
        webView.reload()
    }

    // MARK: - UIWebViewDelegate Method
    
    func webViewDidStartLoad(webView: UIWebView) {
        
        numOfLoadingRequest++
    }
    
    func webViewDidFinishLoad(webView: UIWebView) {

        numOfLoadingRequest--
        
        if (numOfLoadingRequest == 0) {
            
            webviewTitleLb.text = webView.stringByEvaluatingJavaScriptFromString("document.title")
            sendDataToJSBt.enabled = true
            sendDataToJSWithCallBackBt.enabled = true
            callJSHandlerBt.enabled = true
            callJSHandlerWithCallBackBt.enabled = true
            reloadBtItem.enabled = true
            loadingActivity.stopAnimating()
        }
    }
}

