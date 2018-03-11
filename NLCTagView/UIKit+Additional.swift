//
//  UIKit+Additional.swift
//  SCTagView
//
//  Created by SwanCurve on 01/21/18.
//  Copyright © 2018 SwanCurve. All rights reserved.
//

import UIKit

extension CGRect {
    init(x: CGFloat, y: CGFloat, size: CGSize) {
        self.init(x: x, y: y, width: size.width, height: size.height)
    }
}

extension CGSize {
    public static var greatest: CGSize {
        return CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
}

extension OptionSet {
    static func &(rhs: Self, lhs: Self.Element) -> Bool {
        return rhs.contains(lhs)
    }
}

extension NSAttributedString {
    open var entireRange: NSRange {
        return NSRange(location: 0, length: self.length)
    }
}

extension UIFont {
    func sizeAdjust(_ value: CGFloat) -> UIFont {
        let descriptor = self.fontDescriptor
        let size = descriptor.pointSize + value
        let newDescriptor = descriptor.withSize(size)
        return UIFont(descriptor: newDescriptor, size: size)
    }
}
