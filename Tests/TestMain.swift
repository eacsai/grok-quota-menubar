import Foundation

@main
struct TestMain {
    static func main() {
        var failed = 0
        failed += QuotaParserTests.run()
        failed += AuthPolicyTests.run()
        failed += ClashProxyTests.run()
        failed += GrokProcessTests.run()
        failed += BillingClientTests.run()
        failed += AuthLockTests.run()
        if failed == 0 {
            print("all tests passed")
        } else {
            print("FAILED \(failed)")
            exit(1)
        }
    }
}
