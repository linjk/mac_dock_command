import XCTest
@testable import BarCmd

final class ProcessSpawnerTests: XCTestCase {
    func testZshSourcesZshrcAndExports() {
        let args = ProcessSpawner.arguments(command: "npx dsh web", env: ["FOO": "b\"ar"], shellName: "zsh")
        XCTAssertEqual(args[0], "-l")
        XCTAssertEqual(args[1], "-c")
        XCTAssertTrue(args[2].contains("source \"${ZDOTDIR:-$HOME}/.zshrc\""))
        XCTAssertTrue(args[2].contains("export FOO="))
        XCTAssertTrue(args[2].contains("npx dsh web"))
        XCTAssertFalse(args.contains("-i"))
    }

    func testBashSourcesBashrc() {
        let args = ProcessSpawner.arguments(command: "true", env: [:], shellName: "bash")
        XCTAssertTrue(args[2].contains("source \"$HOME/.bashrc\""))
    }
}
