//
//  File 2.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import XCTest
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension StatoscopeTestPlan {
    
    public func configureViewSnapshot<V: View>(_ test: XCTestCase, _ block: @escaping (T) -> V) -> Self {
#if canImport(UIKit)
        snapshot = { sut in
            let screenshot = block(sut).asImage()
            let attachment = XCTAttachment(image: screenshot)
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }
#endif
        return self
    }
    
    public func takeSnapshot(file: StaticString = #file, line: UInt = #line) -> Self {
        return addStep { [weak self] sut in
            XCTAssertNotNil(self?.snapshot, "Taking snapshot without configured snapshot block", file: file, line: line)
            self?.snapshot?(sut)
        }
    }
}

#if canImport(UIKit)
extension View {
    
    func asImage() -> UIImage {
        let controller = UIHostingController(rootView: self)
        let view = controller.view
        let targetSize = UIScreen.main.bounds.size // controller.view.intrinsicContentSize
        let bounds = CGRect(origin: .zero, size: targetSize)
        let window = UIWindow(frame: bounds)
        window.rootViewController = controller
        window.isHidden = false
        view?.bounds = bounds
        view?.backgroundColor = .clear
        view?.layoutIfNeeded()
        controller.view.backgroundColor = .white
        let image = controller.view.asImage()
        window.rootViewController = UIViewController()
        window.isHidden = true
        return image
    }
}

extension UIView {
    func asImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { rendererContext in
            layer.render(in: rendererContext.cgContext)
        }
    }
}
#endif
