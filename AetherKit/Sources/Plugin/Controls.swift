//
//  Controls.swift
//  AetherKit
//
//  Created by Christophe Bronner on 2026-06-06.
//

import Foundation

public enum AnyControl {
	case picker(PickerControl)
	case text(TextControl)
	case toggle(ToggleControl)
}

public struct PickerControl: Control {
	public var title: LocalizedStringResource
	public var help: LocalizedStringResource?
	public var options: [Option] = []

	public init(title: LocalizedStringResource) {
		self.title = title
	}

	public var toAnyControl: AnyControl { .picker(self) }

	public struct Option {
		public var tag: String
		public var title: LocalizedStringResource

		public init(_ title: LocalizedStringResource, is tag: String) {
			self.title = title
			self.tag = tag
		}
	}
}

public struct TextControl: Control {
	public var title: LocalizedStringResource
	public var help: LocalizedStringResource?

	public init(title: LocalizedStringResource) {
		self.title = title
	}

	public var toAnyControl: AnyControl { .text(self) }
}

public struct ToggleControl: Control {
	public var title: LocalizedStringResource
	public var help: LocalizedStringResource?

	public init(title: LocalizedStringResource) {
		self.title = title
	}

	public var toAnyControl: AnyControl { .toggle(self) }
}

public protocol Control {
	init(title: LocalizedStringResource)
	var toAnyControl: AnyControl { get }
}

public extension Control {
	init(
		_ title: LocalizedStringResource,
		build: (inout Self) -> Void
	) {
		self.init(title: title)
		build(&self)
	}
}
