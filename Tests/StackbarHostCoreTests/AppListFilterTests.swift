import XCTest
@testable import StackbarHostCore

final class AppListFilterTests: XCTestCase {
    func testKeepsAppsPeopleOpen() {
        for path in [
            "/Applications/Safari.app",
            "/Applications/Adobe Photoshop 2026/Tools/Adobe Photoshop 2026.app",
            "/Volumes/Work SSD/Apps/Blender.app",
            "/Users/n/Applications/Chrome Apps.localized/Gmail.app",
            "/Users/n/Downloads/Some Tool.app",
            "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app",
            "/Applications/Xcode.app/Contents/Applications/Instruments.app",
        ] {
            XCTAssertTrue(AppListFilter.keeps(path), path)
        }
    }

    func testSkipsHelpersBackupsAndSystemInternals() {
        for path in [
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app",
            "/Applications/Slack.app/Contents/Library/LoginItems/Slack Helper.app",
            "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/Helpers/Helper.app",
            "/System/Library/CoreServices/loginwindow.app",
            "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app",
            "/Users/n/Library/Application Support/Steam/Steam.AppBundle/Steam.app",
            "/Users/n/.Trash/Old.app",
            "/Volumes/Backup/Backups.backupdb/Mac/Latest/Applications/Safari.app",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
            "/private/var/folders/x/Installer.app",
            "/Applications/Notes.txt",
        ] {
            XCTAssertFalse(AppListFilter.keeps(path), path)
        }
    }
}
