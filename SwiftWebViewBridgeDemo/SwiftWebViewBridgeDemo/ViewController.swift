//
//  ViewController.swift
//  SwiftWebViewBridgeDemo
//
//  Created by ShawnFoo on 16/1/20.
//  Copyright © 2016年 ShawnFoo. All rights reserved.
//

import UIKit

// if you install SwiftWebViewBridge by Cocoapods, please remember to import it
// import SwiftWebViewBridge

class ViewController: UIViewController {
    
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
    
    private var bridge: SwiftWebViewBridge!
    
    // MARK: LifeCycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.bridge = SwiftWebViewBridge.bridge(webView, defaultHandler: { data, responseCallback in
            
            print("Swift received message from JS: \(data)")
            
            // Actually, this responseCallback could be an empty closure when javascript has no callback, saving you from unwarping an optional parameter = )
            responseCallback("Swift already got your msg, thanks")
        })
        
        //  SwiftJavaScriptBridge.logging = false
        
        self.bridge.registerHandlerForJS(handlerName: "printReceivedParmas", handler: { [unowned self] jsonData, responseCallback in
            
            // if you used self in any bridge handler/callback closure, remember to declare weak or unowned self, preventing from retaining cycle!
            // Because VC owned bridge, brige owned this closure, and this cloure captured self!
            self.printReceivedParmas(jsonData)
            
            responseCallback(["msg": "Swift has already finished its handler", "returnValue": [1, 2, 3]])
            })
        
        self.bridge.sendDataToJS(["msg": "Hello JavaScript, My name is 小明", "gift": ["100CNY", "1000CNY", "10000CNY"]])
        
        self.loadLocalWebPage()
    }
}

// MARK: - UIViewController + UIWebViewDelegate

extension ViewController: UIWebViewDelegate {
    
    func webViewDidStartLoad(webView: UIWebView) {
        
        self.numOfLoadingRequest++
    }
    
    func webViewDidFinishLoad(webView: UIWebView) {
        
        self.numOfLoadingRequest--
        
        if (self.numOfLoadingRequest == 0) {
            
            self.webviewTitleLb.text = webView.stringByEvaluatingJavaScriptFromString("document.title")
            self.sendDataToJSBt.enabled = true
            self.sendDataToJSWithCallBackBt.enabled = true
            self.callJSHandlerBt.enabled = true
            self.callJSHandlerWithCallBackBt.enabled = true
            self.reloadBtItem.enabled = true
            self.loadingActivity.stopAnimating()
        }
    }
}

// MARK: - ViewController + Actions

extension ViewController {
    
    @IBAction func sendDataToJS(sender: AnyObject) {
        
        self.bridge.sendDataToJS(["msg": "Hello JavaScript", "gift": ["100CNY", "1000CNY", "10000CNY"]])
        
        /* same effect as above, as you can see in SwiftWebViewBridge implementation
        bridge?.callJSHandler(nil, params: ["msg": "Hello JavaScript", "gift": "100CNY"], responseCallback: nil)
        */
    }
    
    @IBAction func sendDataToJSWithCallback(sender: AnyObject) {
        
        self.bridge.sendDataToJS("Did you received my gift, JS?", responseCallback: { data in
            
            print("Receiving JS return gift: \(data)")
        })
    }
    
    @IBAction func callJSHandler(sender: AnyObject) {
        
        self.bridge.callJSHandler("alertReceivedParmas", params: ["msg": "JS, are you there?", "num": 5], responseCallback: nil)
    }
    
    @IBAction func callJSHandlerWithCallback(sender: AnyObject) {
        
        self.bridge.callJSHandler("alertReceivedParmas", params: ["msg": "JS, I know you there!"]) { data in
            
            print("Got response from js: \(data)")
        }
    }
    
    @IBAction func reloadAction(sender: AnyObject) {
        
        self.numOfLoadingRequest = 0
        self.webviewTitleLb.text = ""
        self.loadingActivity.startAnimating()
        self.sendDataToJSBt.enabled = false
        self.sendDataToJSWithCallBackBt.enabled = false
        self.callJSHandlerBt.enabled = false
        self.callJSHandlerWithCallBackBt.enabled = false
        self.reloadBtItem.enabled = false
        self.webView.reload()
    }
    
    private func printReceivedParmas(data: AnyObject) {
        
        print("Swift recieved data passed from JS: \(data)")
    }
    
    private func loadLocalWebPage() {
        
        guard let urlPath = NSBundle.mainBundle().URLForResource("Demo", withExtension: "html") else {
            
            print("Couldn't find the Demo.html file in bundle!")
            return
        }
        
        let request = NSURLRequest(URL: urlPath, cachePolicy: .ReloadIgnoringLocalCacheData, timeoutInterval: 10.0)
        self.webView.loadRequest(request)
    }
}

