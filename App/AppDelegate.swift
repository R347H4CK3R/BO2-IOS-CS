import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        RuntimeLog.stage("APP_START")
        let window = UIWindow(frame: UIScreen.main.bounds)
        let autotest = CommandLine.arguments.contains("AUTOTEST") || ProcessInfo.processInfo.environment["AUTOTEST"] == "1"
        window.rootViewController = autotest ? GameViewController() : BO2MenuViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
