//
//  EKWindowProvider.swift
//  SwiftEntryKit
//
//  Created by Daniel Huri on 4/19/18.
//  Copyright (c) 2018 huri000@gmail.com. All rights reserved.
//

import UIKit

final class EKWindowProvider: EntryPresenterDelegate {
    
    /** The artificial safe area insets */
    static var safeAreaInsets: UIEdgeInsets {
        if #available(iOS 11.0, *) {
            return EKWindowProvider.shared.windows.values.first?.rootViewController?.view?.safeAreaInsets ?? UIApplication.shared.keyWindow?.rootViewController?.view.safeAreaInsets ?? .zero
        } else {
            let statusBarMaxY = UIApplication.shared.statusBarFrame.maxY
            return UIEdgeInsets(top: statusBarMaxY, left: 0, bottom: 10, right: 0)
        }
    }
    
    /** Single access point */
    static let shared = EKWindowProvider()
    
    /** Current entry window */
    var windows: [EKAttributes.WindowLevel: EKWindow] = [:]
    
    /** Returns the root view controller if it is instantiated */
    func rootViewContrller(for windowLevel: EKAttributes.WindowLevel) -> EKRootViewController? {
        return windows[windowLevel]?.rootViewController as? EKRootViewController
    }
    
//    var rootVC: EKRootViewController? {
//        return entryWindow?.rootViewController as? EKRootViewController
//    }
//
    /** A window to go back to when the last entry has been dismissed */
    private var rollbackWindow: SwiftEntryKit.RollbackWindow!

    /** Entry queueing heuristic  */
    private let entryQueue = EKAttributes.Precedence.QueueingHeuristic.value.heuristic
    
    private var entryViews = NSHashTable<EKEntryView>.weakObjects()
    
    /** Cannot be instantiated, customized, inherited */
    private init() {}
    
    func isResponsiveToTouches(for windowLevel: EKAttributes.WindowLevel) -> Bool {
        windows[windowLevel]?.isAbleToReceiveTouches ?? false
    }
    
    func set(isResponsiveToTouches: Bool, for windowLevel: EKAttributes.WindowLevel) {
        windows[windowLevel]?.isAbleToReceiveTouches = isResponsiveToTouches
    }
    
    // MARK: - Setup and Teardown methods
    
    // Prepare the window and the host view controller
    private func prepare(for attributes: EKAttributes, presentInsideKeyWindow: Bool) -> EKRootViewController? {
        let entryVC = setupWindowAndRootVC(with: attributes.windowLevel)
        guard entryVC.canDisplay(attributes: attributes) || attributes.precedence.isEnqueue else {
            return nil
        }
        entryVC.setStatusBarStyle(for: attributes)

        windows[attributes.windowLevel]?.windowLevel = attributes.windowLevel.value
        if presentInsideKeyWindow {
            windows[attributes.windowLevel]?.makeKeyAndVisible()
        } else {
            windows[attributes.windowLevel]?.isHidden = false
        }

        return entryVC
    }
    
    /** Boilerplate generic setup for entry-window and root-view-controller  */
    private func setupWindowAndRootVC(with windowLevel: EKAttributes.WindowLevel) -> EKRootViewController {
        let entryVC: EKRootViewController
        
        if windows[windowLevel] == nil {
            entryVC = EKRootViewController(with: self)
            windows[windowLevel] = EKWindow(with: entryVC)
        } else {
            entryVC = rootViewContrller(for: windowLevel)!
        }
        return entryVC
    }
    
    /**
     Privately used to display an entry
     */
    private func display(entryView: EKEntryView, using attributes: EKAttributes, presentInsideKeyWindow: Bool, rollbackWindow: SwiftEntryKit.RollbackWindow) {
        switch entryView.attributes.precedence {
        case .override(priority: _, dropEnqueuedEntries: let dropEnqueuedEntries):
            if dropEnqueuedEntries {
                entryQueue.removeAll()
            }
            show(entryView: entryView, presentInsideKeyWindow: presentInsideKeyWindow, rollbackWindow: rollbackWindow)
        case .enqueue where isCurrentlyDisplaying():
            entryQueue.enqueue(entry: .init(view: entryView, presentInsideKeyWindow: presentInsideKeyWindow, rollbackWindow: rollbackWindow))
        case .enqueue:
            show(entryView: entryView, presentInsideKeyWindow: presentInsideKeyWindow, rollbackWindow: rollbackWindow)
        }
    }
    
    // MARK: - Exposed Actions
    
    func queueContains(entryNamed name: String? = nil) -> Bool {
        if name == nil && !entryQueue.isEmpty {
            return true
        }
        if let name = name {
            return entryQueue.contains(entryNamed: name)
        } else {
            return false
        }
    }
    
    /**
     Returns *true* if the currently displayed entryes has the given name.
     In case *name* has the value of *nil*, the result is *true* if any entry is currently displayed.
     */
    func isCurrentlyDisplaying(entryNamed name: String? = nil) -> Bool {

        guard let name = name else  {
            return !entryViews.allObjects.isEmpty
        }
//        guard let entryView: EKEntryView = entryViews.first(where: { $0.object?.attributes.name == name })?.object  != nil else {
//            return false
//        }
        
        return entryViews.allObjects.first(where: { $0.attributes.name == name }) != nil
    }
    
    
    /** Display a view using attributes */
    func display(view: UIView, using attributes: EKAttributes, presentInsideKeyWindow: Bool, rollbackWindow: SwiftEntryKit.RollbackWindow) {
        let entryView = EKEntryView(newEntry: .init(view: view, attributes: attributes))
        display(entryView: entryView, using: attributes, presentInsideKeyWindow: presentInsideKeyWindow, rollbackWindow: rollbackWindow)
    }

    /** Display a view controller using attributes */
    func display(viewController: UIViewController, using attributes: EKAttributes, presentInsideKeyWindow: Bool, rollbackWindow: SwiftEntryKit.RollbackWindow) {
        let entryView = EKEntryView(newEntry: .init(viewController: viewController, attributes: attributes))
        display(entryView: entryView, using: attributes, presentInsideKeyWindow: presentInsideKeyWindow, rollbackWindow: rollbackWindow)
    }
    
    /** Clear all entries immediately and display to the rollback window */
    func displayRollbackWindow(for windowLeveL: EKAttributes.WindowLevel) {
        windows[windowLeveL] = nil
        //TODO: Findeoute what's here
//        entryView = nil
        
        switch rollbackWindow! {
        case .main:
            UIApplication.shared.keyWindow?.makeKeyAndVisible()
        case .custom(window: let window):
            window.makeKeyAndVisible()
        }
    }
    
    /** Display a pending entry if there is any inside the queue */
    func displayPendingEntryIfNeeded(for windowLeveL: EKAttributes.WindowLevel) {
        if let next = entryQueue.dequeue() {
            show(entryView: next.view, presentInsideKeyWindow: next.presentInsideKeyWindow, rollbackWindow: next.rollbackWindow)
        } else {
            displayRollbackWindow(for: windowLeveL)
        }
    }
    
    /** Dismiss entries according to a given descriptor */
    func dismiss(_ descriptor: SwiftEntryKit.EntryDismissalDescriptor, with completion: SwiftEntryKit.DismissCompletionHandler? = nil) {
        guard !windows.values.isEmpty else { return }
        
        
        switch descriptor {
        case .displayed:
            // удаляет последний попап с топового виндоу
            guard let rootVC = rootViewContrller(for: .normal) else { // TODO: REDO TO GET
                return
            }
            rootVC.animateOutLastEntry(completionHandler: completion)
            
        case .specific(entryName: let name):
            
            entryQueue.removeEntries(by: name)
            
            guard let entryView = entryViews.allObjects.first(where: { $0.attributes.name == name }) else { return }
            
            guard let rootViewController = rootViewContrller(for: entryView.attributes.windowLevel) else { // TODO: REDO TO GET
                return
            }
            rootViewController.animateOutLastEntry(completionHandler: completion)
            
        case .prioritizedLowerOrEqualTo(priority: let priorityThreshold):
            entryQueue.removeEntries(withPriorityLowerOrEqualTo: priorityThreshold)
            
            // TODO: - operate currently presented entries and remove all with threshold lower than
            windows.values
                .compactMap {
                    $0.rootViewController as? EKRootViewController
                }.filter {
                    $0.lastAttributes.precedence.priority <= priorityThreshold
                }.forEach {
                    $0.animateOutLastEntry(completionHandler: completion)
                }
        case .enqueued:
            entryQueue.removeAll()
        case .all:
            entryQueue.removeAll()
            windows.values.compactMap { $0.rootViewController as? EKRootViewController }.forEach {
                $0.animateOutLastEntry(completionHandler: completion)
            }

        }
    }
    
    /** Layout the view-hierarchy rooted in the window */
    func layoutIfNeeded() {
        windows.values.forEach { $0.layoutIfNeeded() }
    }
    
    /** Privately using to prepare the root view controller and show the entry immediately */
    private func show(entryView: EKEntryView, presentInsideKeyWindow: Bool, rollbackWindow: SwiftEntryKit.RollbackWindow) {
        guard let entryVC = prepare(for: entryView.attributes, presentInsideKeyWindow: presentInsideKeyWindow) else {
            return
        }
        
        entryVC.configure(entryView: entryView)
        entryViews.add(entryView)
        self.rollbackWindow = rollbackWindow
    }
}
