public protocol AetherPlugin {
	init(using services: any AetherServices)
}

public protocol AetherServices {
	func onOpen(do action: OpenPlugin)
	func onLoad(do action: LoadPlugin)
}
