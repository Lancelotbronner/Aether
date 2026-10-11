//
//  AetherPlugin.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-06.
//

public protocol AetherPlugin {
	init(using services: any AetherServices)
}

public protocol AetherServices {
	func onOpen(do action: OpenPlugin)
	func onLoad(do action: LoadPlugin)
}
