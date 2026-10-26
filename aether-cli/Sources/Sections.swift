///// Binary section (e.g., `__text`, `__data`)
//@Model nonisolated final class SectionModel {
//	#Unique<SectionModel>([\.binary, \.address])
//
//	var binary: BinaryModel
//	var segment: SegmentModel
//	var name = "Untitled"
//	var segmentName = "Untitled"
//	var address: UInt64 = 0
//	var size: UInt64 = 0
//	var offset: UInt32 = 0
//	var alignment: UInt32 = 0
//	var flags: UInt32 = 0
//
//	init(in segment: SegmentModel, of binary: BinaryModel) {
//		self.segment = segment
//		self.binary = binary
//	}
//
//}
