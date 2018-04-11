//
//  SwiftyBeaver.swift
//  SwiftyBeaver
//
//  Created by Sebastian Kreutzberger (Twitter @skreutzb) on 28.11.15.
//  Copyright © 2015 Sebastian Kreutzberger
//  Some rights reserved: http://opensource.org/licenses/MIT
//

import Foundation

open class SwiftyBeaver {

    /// version string of framework
    public static let version = "1.5.2"  // UPDATE ON RELEASE!
    /// build number of framework
    public static let build = 1520 // version 0.7.1 -> 710, UPDATE ON RELEASE!

    public enum Level: Int {
        case verbose = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
    }

    /// Whether add to the message sensitive information or not
    public static var logsSensitive: Bool = false
    
    // a set of active destinations
    open private(set) static var destinations = Set<BaseDestination>()

    // MARK: Destination Handling

    /// returns boolean about success
    @discardableResult
    open class func addDestination(_ destination: BaseDestination) -> Bool {
        if destinations.contains(destination) {
            return false
        }
        destinations.insert(destination)
        return true
    }

    /// returns boolean about success
    @discardableResult
    open class func removeDestination(_ destination: BaseDestination) -> Bool {
        if destinations.contains(destination) == false {
            return false
        }
        destinations.remove(destination)
        return true
    }

    /// if you need to start fresh
    open class func removeAllDestinations() {
        destinations.removeAll()
    }

    /// returns the amount of destinations
    open class func countDestinations() -> Int {
        return destinations.count
    }

    /// returns the current thread name
    class func threadName() -> String {

        #if os(Linux)
            // on 9/30/2016 not yet implemented in server-side Swift:
            // > import Foundation
            // > Thread.isMainThread
            return ""
        #else
            if Thread.isMainThread {
                return ""
            } else {
                let threadName = Thread.current.name
                if let threadName = threadName, !threadName.isEmpty {
                    return threadName
                } else {
                    return String(format: "%p", Thread.current)
                }
            }
        #endif
    }

    // MARK: Levels

    /// log something generally unimportant (lowest priority)
    open class func verbose(_ message: @autoclosure () -> Any, sensitive: String? = nil, _
        file: String = #file, _ function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .verbose, message: message, sensitive: sensitive, file: file, function: function, line: line, context: context)
    }

    /// log something which help during debugging (low priority)
    open class func debug(_ message: @autoclosure () -> Any, sensitive: String? = nil, _
        file: String = #file, _ function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .debug, message: message, sensitive: sensitive, file: file, function: function, line: line, context: context)
    }

    /// log something which you are really interested but which is not an issue or error (normal priority)
    open class func info(_ message: @autoclosure () -> Any, sensitive: String? = nil, _
        file: String = #file, _ function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .info, message: message, sensitive: sensitive, file: file, function: function, line: line, context: context)
    }

    /// log something which may cause big trouble soon (high priority)
    open class func warning(_ message: @autoclosure () -> Any, sensitive: String? = nil, _
        file: String = #file, _ function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .warning, message: message, sensitive: sensitive, file: file, function: function, line: line, context: context)
    }

    /// log something which will keep you awake at night (highest priority)
    open class func error(_ message: @autoclosure () -> Any, sensitive: String? = nil, _
        file: String = #file, _ function: String = #function, line: Int = #line, context: Any? = nil) {
        custom(level: .error, message: message, sensitive: sensitive, file: file, function: function, line: line, context: context)
    }

    /// custom logging to manually adjust values, should just be used by other frameworks
    public class func custom(level: SwiftyBeaver.Level, message: @autoclosure () -> Any, sensitive: String?,
                             file: String = #file, function: String = #function, line: Int = #line, context: Any? = nil) {
        dispatch_send(level: level, message: message, sensitive: sensitive, thread: threadName(),
                      file: file, function: function, line: line, context: context)
    }

    /// internal helper which dispatches send to dedicated queue if minLevel is ok
    class func dispatch_send(level: SwiftyBeaver.Level, message: @autoclosure () -> Any, sensitive: String?,
        thread: String, file: String, function: String, line: Int, context: Any?) {
        var resolvedMessage: String?
        for dest in destinations {

            guard let queue = dest.queue else {
                continue
            }

            let includeSensitive = (logsSensitive && sensitive?.isEmpty == false)
            resolvedMessage = resolvedMessage == nil && dest.hasMessageFilters() ? "\(message())" + (includeSensitive ? "; \(sensitive!)" : "") : resolvedMessage
            if dest.shouldLevelBeLogged(level, path: file, function: function, message: resolvedMessage) {
                // try to convert msg object to String and put it on queue
                let msgStr = resolvedMessage == nil ? "\(message())" + (includeSensitive ? "; \(sensitive!)" : "") : resolvedMessage!
                let f = stripParams(function: function)

                if dest.asynchronously {
                    queue.async {
                        _ = dest.send(level, msg: msgStr, thread: thread, file: file, function: f, line: line, context: context)
                    }
                } else {
                    queue.sync {
                        _ = dest.send(level, msg: msgStr, thread: thread, file: file, function: f, line: line, context: context)
                    }
                }
            }
        }
    }

    /**
     Flush all destinations to make sure all logging messages have been written out
     Returns after all messages flushed or timeout seconds

     - returns: true if all messages flushed, false if timeout or error occurred
     */
    public class func flush(secondTimeout: Int) -> Bool {
        let grp = DispatchGroup()
        for dest in destinations {
            if let queue = dest.queue {
                grp.enter()
                queue.async {
                    dest.flush()
                    grp.leave()
                }
            }
        }
        let timeout: DispatchTime = .now() + .seconds(secondTimeout)
        return grp.wait(timeout: timeout) == .success
    }

    /// removes the parameters from a function because it looks weird with a single param
    class func stripParams(function: String) -> String {
        var f = function
        if let indexOfBrace = f.find("(") {
            #if swift(>=4.0)
            f = String(f[..<indexOfBrace])
            #else
            f = f.substring(to: indexOfBrace)
            #endif
        }
        f += "()"
        return f
    }
}
