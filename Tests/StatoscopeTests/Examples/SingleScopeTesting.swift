//
//  SingleScopeTesting.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 21/11/24.
//

import XCTest
@testable import Statoscope

class SingleScopeTesting: XCTestCase {
    
    final class UserNotificationsNoEffects: Statostore, ObservableObject {
        @Published var notificationsPermissions: Bool = false
        enum When {
            case userTapsEnableNotifications
        }
        func update(_ when: When) throws {
            switch when {
            case .userTapsEnableNotifications:
                notificationsPermissions = !notificationsPermissions
            }
        }
    }
    
    func testUserNotificationsNoEffects() throws {
        try UserNotificationsNoEffects.GIVEN {
            UserNotificationsNoEffects()
        }
        .THEN(\.notificationsPermissions, equals: false)
        .WHEN(.userTapsEnableNotifications)
        .THEN(\.notificationsPermissions, equals: true)
        .runTest()
    }
    
    final class UserNotifications: Statostore, ObservableObject {
        
        enum NotificationPermissions {
            case unknown
            case requesting
            case allowed
            case denied
        }
        @EffectStruct
        static func requestPermissions() async throws -> NotificationPermissions {
            try await Task.sleep(nanoseconds: 100_000_000)
            return .allowed
        }

        @Published var notificationsPermissions: NotificationPermissions = .unknown
        enum When {
            case userTapsEnableNotifications
            case systemRespondsToNotificationPermissionRequest(NotificationPermissions)
        }
        func update(_ when: When) throws {
            switch when {
            case .userTapsEnableNotifications:
                notificationsPermissions = .requesting
                effectsState.enqueue(
                    RequestPermissionsEffect()
                        .map(When.systemRespondsToNotificationPermissionRequest)
                )
            case .systemRespondsToNotificationPermissionRequest(let newPermissions):
                notificationsPermissions = newPermissions
            }
        }
    }
    
    func testUserNotificationsAllowed() throws {
        try UserNotifications.GIVEN {
            UserNotifications()
        }
        .THEN(\.notificationsPermissions, equals: .unknown)
        .WHEN(.userTapsEnableNotifications)
        .THEN(\.notificationsPermissions, equals: .requesting)
        .WHEN_EffectCompletes(UserNotifications.RequestPermissionsEffect.self, with: .allowed)
        .THEN(\.notificationsPermissions, equals: .allowed)
        .runTest()
    }
    
    func testUserNotificationsDenied() throws {
        try UserNotifications.GIVEN {
            UserNotifications()
        }
        .THEN(\.notificationsPermissions, equals: .unknown)
        .WHEN(.userTapsEnableNotifications)
        .THEN(\.notificationsPermissions, equals: .requesting)
        .WHEN_OlderEffectCompletes(with: .systemRespondsToNotificationPermissionRequest(.denied))
        .THEN(\.notificationsPermissions, equals: .denied)
        .runTest()
    }
    
    func testUserNotificationsFork() throws {
        try UserNotifications.GIVEN {
            UserNotifications()
        }
        .THEN(\.notificationsPermissions, equals: .unknown)
        .WHEN(.userTapsEnableNotifications)
        .THEN(\.notificationsPermissions, equals: .requesting)
        .FORK_OlderEffectCompletes(with: .systemRespondsToNotificationPermissionRequest(.denied)) { try $0
            .THEN(\.notificationsPermissions, equals: .denied)
        }
        .WHEN_OlderEffectCompletes(with: .systemRespondsToNotificationPermissionRequest(.allowed))
        .THEN(\.notificationsPermissions, equals: .allowed)
        .runTest()
    }
    
    func testUserNotificationsEffectsCheck() throws {
        try UserNotifications.GIVEN {
            UserNotifications()
        }
        .THEN(\.notificationsPermissions, equals: .unknown)
        .THEN_NoEffects()
        .WHEN(.userTapsEnableNotifications)
        .THEN(\.notificationsPermissions, equals: .requesting)
        .WHEN_EffectCompletes(
            UserNotifications.RequestPermissionsEffect.self,
            with: .allowed
        )
        .THEN_NoEffects()
        .THEN(\.notificationsPermissions, equals: .allowed)
        .runTest()
    }
}

