//
//  ShareViewController.swift
//  MapNote Share Extension
//
//  Receives text/links shared from other apps and hands them to the main
//  MapNote app, which parses them with LocationParser.
//
import receive_sharing_intent

class ShareViewController: RSIShareViewController {

    // Redirect straight to MapNote once the share is handled.
    override func shouldAutoRedirect() -> Bool {
        return true
    }
}
