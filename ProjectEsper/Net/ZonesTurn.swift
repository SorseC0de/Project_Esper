import EsperSim
import Foundation

/// A ZONES turn as Game Center keeps it between phones: the game's state, with the run set
/// in it, each side's FloState pick, and each side's look. The protocol version is the
/// sim's, so a phone on another build says so rather than playing a different game.
struct ZonesTurn: Codable {
    var version = NetRules.protocolVersion
    var game: ZonesGame
    var powers: [Power]
    var sides: [PlayerCustomization?]

    enum Problem: Error { case unreadable, otherVersion }

    static func decode(_ data: Data) throws -> ZonesTurn {
        guard let turn = try? JSONDecoder().decode(ZonesTurn.self, from: data) else { throw Problem.unreadable }
        guard turn.version == NetRules.protocolVersion else { throw Problem.otherVersion }
        return turn
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
}
