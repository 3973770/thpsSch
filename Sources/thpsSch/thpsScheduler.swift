//
//  File.swift
//  
//
//  Created by Kostiantyn Bohonos on 2/7/22.
//

import Foundation
import thpslibs

public class thpsScheduler{
    private static let socketLockQueue = DispatchQueue(label: "com.thps.Scheduler")
    private static let sema = DispatchSemaphore(value: 1)
    private static var continueRunningValue = true
    private static var continueRunning: Bool {
        set(newValue) {
            socketLockQueue.sync {
                continueRunningValue = newValue
            }
        }
        get {
            var res:Bool = false
            socketLockQueue.sync{
                res = continueRunningValue
            }
            return res
        }
    }
    private static var list:[String:thpsSchedulerItem] = [:]
    
    public static func Add(item:thpsSchedulerItem){
        if !list.keys.contains(item.key!) {
            list[item.key!] = item
        }
    }
    
    public static func Remove(key:String){
        list.removeValue(forKey: key)
    }
    
    public static func RunForced(key:String){
        if list.keys.contains(key) {
            if let task = list[key] {
                task.RunForced()
            }
        }
    }
    
    public static func Run(){
        DispatchQueue.global(qos: .utility).async{
            repeat {
                for (_, task) in list {
                    task.Run()
                }
                Thread.sleep(forTimeInterval: 1.0)
            } while continueRunning
        }
        
    }
    public static func Stop() {
        continueRunning = false
    }
}

/// Plan for execution of the task
public class thpsSchedulerPlan{
    public var ItemType:thpsSchedulerPlanType?
    public var interval:UInt64?
    public var MomentStart:Date?
    public var MomentEnd:Date?
    public var TimeStart:Date?
    public var TimeEnd:Date?
    public var DayOfWeeks:[Int8]?
    public var lastrun:Date?
    
    init(MomentPlanned:Date) {
        ItemType    = .planned
        MomentStart = MomentPlanned
    }
    
    init(interval:UInt64){
        ItemType      = .period
        self.interval = interval
    }
    
    public func markrun(){
        lastrun = thpsDT.CurrentMoment
    }
}

open class thpsSchedulerItem {
    public var key:String?
    public var state:thpsSchedulerState?
    public var plan:thpsSchedulerPlan?
    public var ItemType:thpsSchedulerType?
    public var data:String?
    public var silent:Bool?
    
    init (key:String,plan:thpsSchedulerPlan,ItemType:thpsSchedulerType = .system,silent:Bool = true){
        state = .stop
        self.key = key
        self.ItemType = ItemType
        self.silent = silent
        self.plan = plan
        thpsScheduler.Add(item: self)
    }
    
    public func CheckStart()-> Bool{
        if let ItemType = plan?.ItemType {
            switch ItemType {
                case .planned:
                    return CheckStartPlanned()
                case .period:
                    return CheckStartPeriod()
            }
        }
        return false
    }
    
    public func CheckStartPlanned()->Bool{
        if let plan = plan {
            if let MomentStart = plan.MomentStart {
                let tm:Int64 = thpsDT.DT_momentI()
                let ms:Int64 = thpsDT.DT_momentI(MomentStart)
                if (ms-tm)>0 {
                    return false
                }
            }
            if state == .complited {
                return false
            }
            return true
        }
        return false
    }
        
    
    public func CheckStartPeriod() -> Bool{
        if let plan = plan {
            let tm = thpsDT.DT_momentI()
            if let lastrun = plan.lastrun, let interval = plan.interval {
                let lr = thpsDT.DT_momentI(lastrun)
                let delta = (tm-lr)/1000
                if delta < interval {
                    return false
                }
            }
            if let DayOfWeeks = plan.DayOfWeeks {
                let dayofweek = thpsDT.DT_dayofweek(thpsDT.CurrentMoment)
                if !DayOfWeeks.contains(dayofweek) {
                    return false
                }
            }
            if let MomentStart = plan.MomentStart, let MomentEnd = plan.MomentEnd {
                let ms = thpsDT.DT_momentI(MomentStart)
                let me = thpsDT.DT_momentI(MomentEnd)
                if !((ms<=tm)&&(tm<=me)) {
                    return false
                }
            }else if let MomentStart = plan.MomentStart {
                let ms = thpsDT.DT_momentI(MomentStart)
                if (ms-tm)>0 {
                    return false
                }
            }
            if let TimeStart = plan.TimeStart, let TimeEnd = plan.TimeEnd{
                let ts = thpsDT.DT_momentI(TimeStart)
                let te = thpsDT.DT_momentI(TimeEnd)
                let tt = thpsDT.DT_momentI(thpsDT.DT_time(thpsDT.Display(thpsDT.CurrentMoment, .HMSC)))
                if !((ts<=tt)&&(tt<=te)) {
                    return false
                }
            }
            return true
        }
        return false
    }
    
    public func RunForced() {
        state = .running
        plan?.markrun()
        DispatchQueue.global(qos: .utility).async {
            self.Work()
        }
    }
    
    open func Run() {
        if(CheckStart()){
            if let _ = silent {
                // do something
            }
            state = .running
            plan?.markrun()
            DispatchQueue.global(qos: .utility).async {
                self.Work()
            }
        }
    }
    
    open func End() {
        self.state = thpsSchedulerState.stop
        if let plan = plan {
            plan.markrun()
            if plan.ItemType == thpsSchedulerPlanType.planned{
                thpsScheduler.Remove(key: self.key!)
            }
        }
    }
    
    open func Work(){
        // place own code
    }
}

/// type of start task
public enum thpsSchedulerPlanType:Int8{
    /// repeat task by time intervar
    case period     = 0
    /// run at moment
    case planned    = 1
}

/// states of tasks
public enum thpsSchedulerState:Int8{
    case cancel     = -1
    case stop       = 0
    case running    = 1
    case complited  = 2
}

/// user or system task
public enum thpsSchedulerType:Int8{
    case system = 0
    case user = 1
}
