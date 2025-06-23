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

extension StoreTestPlan {

    public func configureViewSnapshot<V: View>(
        _ test: XCTestCase,
        _ block: @escaping (T) -> V
    ) -> Self {
#if canImport(UIKit)
        snapshot = { sut, name in
            let screenshot = block(sut).asImage()
            let attachment = XCTAttachment(image: screenshot)
            attachment.lifetime = .keepAlways
            if let name {
                attachment.name = name
            }
            test.add(attachment)
        }
#elseif canImport(AppKit)
        snapshot = { sut, name in
            let view = block(sut)
            let image = NSImage(size: CGSize(width: 300, height: 300)) // or your size
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: image.size)
            
            let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)!
            hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
            image.addRepresentation(rep)
            
            if let tiffData = image.tiffRepresentation {
                let attachment = XCTAttachment(data: tiffData, uniformTypeIdentifier: "public.tiff")
                attachment.lifetime = .keepAlways
                if let name { attachment.name = name }
                test.add(attachment)
            }
        }
#endif
        return self
    }

    public func takeSnapshot(name: String? = nil, file: StaticString = #file, line: UInt = #line) -> Self {
        addStep(
            Step(type: .snapshot) { [weak self] sut in
                guard let self else {
                    return XCTFail(
                        "Taking snapshot without configured snapshot block", file: file, line: line
                    )
                }
                self.snapshot?(sut, name)
            }
        )
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
