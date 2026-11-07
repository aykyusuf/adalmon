import Foundation

// AdalmonHelper: SMAppService.daemon olarak root çalışır. Elle çalıştırılırsa Mach servisi kaydolmaz ve hiçbir şey yazmaz.
let runner = HelperRunner()
runner.start()
RunLoop.main.run()
