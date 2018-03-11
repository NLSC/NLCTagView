//
//  ViewController.swift
//  SCTagField
//
//  Created by SwanCurve on 01/21/18.
//  Copyright © 2018 SwanCurve. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    var tagView: NLCTagView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.view.backgroundColor = UIColor.lightGray
        let defaultFont = UIFont.systemFont(ofSize: 20)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = 2
        
        tagView = NLCTagView()
        tagView?.defaultFont = defaultFont
        tagView?.defaultAttributes = [.font : defaultFont,
                                      .paragraphStyle : paraStyle.copy() as! NSParagraphStyle]
        self.tagView?.becomeFirstResponder()
        view.addSubview(tagView!)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tagView?.frame = CGRect(x: 0, y: 20, width: view.bounds.width, height: view.bounds.height)
    }
}

