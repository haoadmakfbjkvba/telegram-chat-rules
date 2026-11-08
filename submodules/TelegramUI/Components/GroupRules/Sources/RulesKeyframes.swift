import Foundation
import UIKit
import Display

/// Keyframes that start after `delay` and hold their first value until then. They are taken off when they end, so their
/// last value has to be the layer's own (a layer left holding an ended animation, even at its rest value, can be drawn
/// resampled and soft).
public func rulesAddKeyframes(_ layer: CALayer, keyPath: String, values: [Any], keyTimes: [NSNumber], duration: Double, delay: Double, timing: CAMediaTimingFunctionName = .easeInEaseOut) {
    let animation = CAKeyframeAnimation(keyPath: keyPath)
    animation.values = values
    animation.keyTimes = keyTimes
    animation.duration = duration
    animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
    animation.fillMode = .both
    animation.isRemovedOnCompletion = true
    animation.timingFunction = CAMediaTimingFunction(name: timing)
    layer.add(animation, forKey: keyPath)
}
