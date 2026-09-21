import XCTest
@testable import AgentSpaceCore

/// The sentence a refused shared buffer turns into, and the value behind it.
///
/// Three audiences read this failure and none of them wants the same thing: the
/// log wants the call and the errno, Diagnostics wants the text, and the GUI wants
/// to know that *this* is the failure it can describe usefully to a person holding
/// a mouse. What must not happen is the wire growing a field for it — older peers
/// decode errors strictly, so a new code turns a report into a decode failure.
final class SharedFrameAllocationTests: XCTestCase {
    func testMessageNamesTheCallTheErrnoAndWhatWasAskedFor() {
        let tooLong = SharedFrameAllocationFailure(operation: .create, systemErrorCode: ENAMETOOLONG, attemptedNameBytes: 48)
        XCTAssertEqual(tooLong.message,
                       "shared frame allocation failed: shm_open ENAMETOOLONG (File name too long), attempted 48-byte name against a 31-byte limit")
        let mapped = SharedFrameAllocationFailure(operation: .map, systemErrorCode: ENOMEM, requestedBytes: 1_112_961)
        XCTAssertEqual(mapped.message,
                       "shared frame allocation failed: mmap ENOMEM (Cannot allocate memory), requested 1112961 bytes")
        // The symbolic name and the human one are both in the sentence: one is
        // greppable against the man page, the other needs no lookup.
        XCTAssertEqual(SharedFrameAllocation.systemErrorName(E2BIG), "E2BIG")
        XCTAssertEqual(SharedFrameAllocation.systemErrorName(4242), "errno 4242",
                       "a code these calls were never documented to return still reports its number")
    }

    /// The GUI reads this to decide whether to show a person an action rather than
    /// a syscall. Every operation has to survive the round trip, and an unrelated
    /// failure has to stay unrelated — a stream that merely stopped is not a buffer
    /// that could not be created, and the copy differs.
    func testEveryRefusalRoundTripsThroughItsOwnMessage() {
        for operation in SharedFrameAllocationOperation.allCases {
            let failure = SharedFrameAllocationFailure(operation: operation, systemErrorCode: EACCES, requestedBytes: 4096)
            XCTAssertEqual(SharedFrameAllocation.classify(message: failure.message), operation, failure.message)
        }
        for unrelated in ["frame stream is not running", "SESSION_IS_CONSOLE", "", "shared frame allocation failed",
                          "shared frame allocation failed: somethingElse EPERM"] {
            XCTAssertNil(SharedFrameAllocation.classify(message: unrelated), unrelated)
        }
    }

    /// What a peer that cannot be asked receives. `.internalError` rather than a new
    /// code is the point: an `AgentSpaceErrorCode` case added here would make every
    /// viewer older than this release fail to decode the error at all, which is a
    /// worse failure than the one being reported.
    func testTheWireFormIsAnOrdinaryInternalError() throws {
        let failure = SharedFrameAllocationError(operation: .create, systemErrorCode: ENAMETOOLONG, attemptedNameBytes: 48)
        let error = failure.agentSpaceError
        XCTAssertEqual(error.code, .internalError)
        XCTAssertEqual(error.message, failure.message)
        let decoded = try JSONDecoder().decode(AgentSpaceError.self, from: JSONEncoder().encode(error))
        XCTAssertEqual(decoded, error)
        XCTAssertTrue(decoded.message.hasPrefix(SharedFrameAllocation.messagePrefix), decoded.message)
    }

    /// The typed form crosses as a value inside `frame.stats`, so the fields a
    /// viewer branches on have to arrive intact — and the random name, which is not
    /// among them, must not appear anywhere in the bytes.
    func testTheTypedFailureEncodesWithoutItsName() throws {
        let failure = SharedFrameAllocationFailure(operation: .resize, systemErrorCode: EFBIG, requestedBytes: 8_388_608, attemptedNameBytes: 28)
        let data = try JSONEncoder().encode(failure)
        let decoded = try JSONDecoder().decode(SharedFrameAllocationFailure.self, from: data)
        XCTAssertEqual(decoded, failure)
        XCTAssertEqual(decoded.systemErrorName, "EFBIG", "a viewer reads the errno name off the code it decoded")
        let text = String(data: data, encoding: .utf8) ?? ""
        // The operation crosses as the syscall that refused, not as the case
        // spelled for the publisher's convenience, because the reader of this
        // record is a person holding a man page.
        XCTAssertTrue(text.contains("\"operation\":\"ftruncate\""), text)
        XCTAssertTrue(text.contains("\"systemErrorCode\":27"), text)
        XCTAssertTrue(text.contains("8388608"), text)
        XCTAssertFalse(text.contains("/as-"), "a name belongs in no record: \(text)")
    }

    /// What the report says about a stream that never failed. The worker's
    /// `frame.stats` reply is built field by field from this struct, so the
    /// defaults are the answer a healthy stream gives — a zero and an absent
    /// failure, not keys a reader has to guess about.
    func testAStreamThatNeverFailedStillAnswersBothNewFields() throws {
        var stats = FrameStats()
        XCTAssertEqual(stats.videoEncoderFailures, 0)
        XCTAssertNil(stats.allocationFailure)

        stats.videoEncoderActivations = 4
        stats.videoEncoderFailures = 3
        stats.allocationFailure = SharedFrameAllocationFailure(operation: .create, systemErrorCode: ENAMETOOLONG,
                                                               attemptedNameBytes: 48)
        let decoded = try JSONDecoder().decode(FrameStats.self, from: JSONEncoder().encode(stats))
        XCTAssertEqual(decoded, stats, "both new fields have to survive the report")
        XCTAssertEqual(decoded.allocationFailure?.systemErrorName, "ENAMETOOLONG")
    }
}
