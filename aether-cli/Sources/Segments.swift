///// Binary segment (e.g., `__TEXT`, `__DATA`)
//@Model nonisolated final class SegmentModel {
//	#Unique<SegmentModel>([\.binary, \.address])
//
//	var binary: BinaryModel
//	var name = "Untitled"
//	var address: UInt64 = 0
//	var size: UInt64 = 0
//	var fileOffset: UInt64 = 0
//	var fileSize: UInt64 = 0
//	var maxProtection: UInt32 = 0
//	var initProtection: UInt32 = 0
//
//	@Relationship(deleteRule: .cascade, inverse: \SectionModel.segment)
//	var sections: [SectionModel] = []
//
//	init(in binary: BinaryModel) {
//		self.binary = binary
//	}
//}
