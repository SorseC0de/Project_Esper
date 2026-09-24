import Foundation

/// The netcode's numbers. Inputs go over the wire by frame; the local input is held this
/// many frames before it's simulated, so the remote's has time to arrive; the sim runs at
/// most this far past the last remote input it knows, predicting it as held; and every
/// packet carries this many of the newest inputs, so a lost packet costs nothing.
public enum NetRules {
    public static let protocolVersion: UInt8 = 1
    public static let inputDelay = 2
    public static let predictionWindow = 8
    public static let redundantInputs = 8
    /// The most inputs one packet carries: everything the other side hasn't acknowledged,
    /// up to this.
    public static let maxInputsPerPacket = 64
    /// Frames between looks at who's ahead, and the most frames to hold back at once.
    public static let syncEveryFrames = 10
    public static let syncMaxStall = 4
}

extension PlayerInput {
    /// Each axis in 127 steps a side, as it goes over the wire, so both sides simulate the
    /// same value.
    public var quantized: PlayerInput {
        func step(_ value: Double) -> Double { Double(Int8(clamping: Int((value * 127).rounded()))) / 127 }
        return PlayerInput(stick: Vec2(x: step(stick.x), y: step(stick.y)), aim: Vec2(x: step(aim.x), y: step(aim.y)),
                           jump: jump, shootButtons: shootButtons & 0x7, throwBall: throwBall, taunt: taunt)
    }

    static let wireBytes = 5

    /// Five bytes: the stick, the aim, the buttons.
    func encode(into data: inout Data) {
        func byte(_ value: Double) -> UInt8 { UInt8(bitPattern: Int8(clamping: Int((value * 127).rounded()))) }
        data.append(byte(stick.x))
        data.append(byte(stick.y))
        data.append(byte(aim.x))
        data.append(byte(aim.y))
        let buttons: UInt8 = (jump ? 1 : 0) | ((shootButtons & 0x7) << 1) | (throwBall ? 1 << 4 : 0) | (taunt ? 1 << 5 : 0)
        data.append(buttons)
    }

    static func decode(_ bytes: [UInt8], at offset: Int) -> PlayerInput {
        func axis(_ byte: UInt8) -> Double { Double(Int8(bitPattern: byte)) / 127 }
        let buttons = bytes[offset + 4]
        return PlayerInput(stick: Vec2(x: axis(bytes[offset]), y: axis(bytes[offset + 1])),
                           aim: Vec2(x: axis(bytes[offset + 2]), y: axis(bytes[offset + 3])),
                           jump: buttons & 1 != 0, shootButtons: (buttons >> 1) & 0x7,
                           throwBall: buttons & (1 << 4) != 0, taunt: buttons & (1 << 5) != 0)
    }
}

/// One side's inputs the other hasn't acknowledged, by frame, with where its sim is, how
/// far ahead of the other it thinks it is, the last of the other's frames it holds every
/// input through, and a checksum of its state before `checkFrame`, so a desync shows.
public struct InputPacket: Equatable {
    public var frame: Int
    public var advantage: Int
    public var firstFrame: Int
    public var inputs: [PlayerInput]
    public var knownThrough: Int
    public var checkFrame: Int
    public var checksum: UInt32

    public init(frame: Int, advantage: Int, firstFrame: Int, inputs: [PlayerInput], knownThrough: Int = -1,
                checkFrame: Int = -1, checksum: UInt32 = 0) {
        self.frame = frame
        self.advantage = advantage
        self.firstFrame = firstFrame
        self.inputs = inputs
        self.knownThrough = knownThrough
        self.checkFrame = checkFrame
        self.checksum = checksum
    }
}

/// Everything that crosses between two phones. Inputs go unreliably, every tick; the rest
/// reliably, once.
public enum NetMessage: Equatable {
    /// Each side's random, at the start; the series' seed is the two together.
    case hello(random: UInt32, version: UInt8)
    case inputs(InputPacket)
    /// The scored-on side's drink for the round: its index in the offers both sides rolled.
    case pick(round: Int, choice: Int)
    /// After the win: another series, on a fresh seed from both randoms.
    case rematch(random: UInt32)
    case bye

    private enum Tag: UInt8 { case hello = 1, inputs, pick, rematch, bye }

    public var data: Data {
        var data = Data()
        switch self {
        case .hello(let random, let version):
            data.append(Tag.hello.rawValue)
            data.append(version)
            data.append(uint32: random)
        case .inputs(let packet):
            data.append(Tag.inputs.rawValue)
            data.append(int32: Int32(packet.frame))
            data.append(int32: Int32(packet.advantage))
            data.append(int32: Int32(packet.firstFrame))
            data.append(int32: Int32(packet.checkFrame))
            data.append(uint32: packet.checksum)
            data.append(int32: Int32(packet.knownThrough))
            data.append(UInt8(min(packet.inputs.count, 255)))
            for input in packet.inputs.prefix(255) { input.encode(into: &data) }
        case .pick(let round, let choice):
            data.append(Tag.pick.rawValue)
            data.append(int32: Int32(round))
            data.append(UInt8(clamping: choice))
        case .rematch(let random):
            data.append(Tag.rematch.rawValue)
            data.append(uint32: random)
        case .bye:
            data.append(Tag.bye.rawValue)
        }
        return data
    }

    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard let first = bytes.first, let tag = Tag(rawValue: first) else { return nil }
        switch tag {
        case .hello:
            guard bytes.count >= 6 else { return nil }
            self = .hello(random: bytes.uint32(at: 2), version: bytes[1])
        case .inputs:
            let header = 26
            guard bytes.count >= header else { return nil }
            let count = Int(bytes[header - 1])
            guard bytes.count >= header + count * PlayerInput.wireBytes else { return nil }
            let inputs = (0..<count).map { PlayerInput.decode(bytes, at: header + $0 * PlayerInput.wireBytes) }
            self = .inputs(InputPacket(frame: Int(bytes.int32(at: 1)), advantage: Int(bytes.int32(at: 5)),
                                       firstFrame: Int(bytes.int32(at: 9)), inputs: inputs,
                                       knownThrough: Int(bytes.int32(at: 21)),
                                       checkFrame: Int(bytes.int32(at: 13)), checksum: bytes.uint32(at: 17)))
        case .pick:
            guard bytes.count >= 6 else { return nil }
            self = .pick(round: Int(bytes.int32(at: 1)), choice: Int(bytes[5]))
        case .rematch:
            guard bytes.count >= 5 else { return nil }
            self = .rematch(random: bytes.uint32(at: 1))
        case .bye:
            self = .bye
        }
    }
}

extension Data {
    mutating func append(uint32 value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }

    mutating func append(int32 value: Int32) {
        append(uint32: UInt32(bitPattern: value))
    }
}

extension Array where Element == UInt8 {
    func uint32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 { value |= UInt32(self[offset + index]) << UInt32(index * 8) }
        return value
    }

    func int32(at offset: Int) -> Int32 {
        Int32(bitPattern: uint32(at: offset))
    }
}

extension Match {
    /// A checksum of what matters: where everyone and the ball are, what's held, the
    /// scores and the frame. Two sides on the same frame with different sums have split.
    public var checksum: UInt32 {
        var hash: UInt32 = 2166136261
        func mix(_ value: UInt32) {
            hash ^= value
            hash = hash &* 16777619
        }
        func mix(_ value: Double) {
            let bits = value.bitPattern
            mix(UInt32(truncatingIfNeeded: bits))
            mix(UInt32(truncatingIfNeeded: bits >> 32))
        }
        mix(UInt32(truncatingIfNeeded: frame))
        mix(UInt32(truncatingIfNeeded: countdown))
        for player in players {
            mix(player.position.x)
            mix(player.position.y)
            mix(player.velocity.x)
            mix(player.velocity.y)
            mix(UInt32(truncatingIfNeeded: player.stateTimer))
            mix(UInt32(player.hasBall ? 1 : 0))
        }
        mix(ball.position.x)
        mix(ball.position.y)
        mix(ball.velocity.x)
        mix(ball.velocity.y)
        for score in scores { mix(UInt32(truncatingIfNeeded: score)) }
        for helmet in helmets {
            mix(helmet.box.min.x)
            mix(helmet.box.min.y)
        }
        if let portal { mix(portal.centre.x) }
        return hash
    }
}
