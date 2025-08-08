import Quickshell.Io

Process {
    id: idleRoot
    
    // Uses systemd-inhibit to prevent idle/sleep
    command: ["systemd-inhibit", "--what=idle:sleep", "--who=noctalia", "--why=User requested", "sleep", "infinity"]
    
    // Track background process state
    property bool isRunning: running
    
    onStarted: {
        console.log("[IdleInhibitor] Process started - idle inhibited")
    }
    
    onExited: function(exitCode, exitStatus) {
        console.log("[IdleInhibitor] Process finished:", exitCode)
    }


    function start() {
        if (!running) {
            console.log("[IdleInhibitor] Starting idle inhibitor...")
            running = true
        }
    }
    
    function stop() {
        if (running) {
            // Force stop the process by setting running to false
            running = false
            console.log("[IdleInhibitor] Stopping idle inhibitor...")
        }
    }
    
    function toggle() {
        if (running) {
            stop()
        } else {
            start()
        }
    }
}
