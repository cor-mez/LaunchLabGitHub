import UIKit

class OrientationLockedWindow: UIWindow {
    override var rootViewController: UIViewController? {
        didSet { UIViewController.attemptRotationToDeviceOrientation() }
    }
}
