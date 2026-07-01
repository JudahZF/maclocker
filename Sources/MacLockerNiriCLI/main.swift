import MacLockerNiriCore
import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

func main() -> Int32 {
    do {
        let options = try parseOptions(CommandLine.arguments)
        return try Runner().run(options)
    } catch MacLockerNiriError.help {
        print(usageText)
        return 0
    } catch {
        FileHandle.standardError.write(Data("maclocker-niri: \(error)\n".utf8))
        return 2
    }
}

exit(main())
