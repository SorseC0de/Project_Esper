@testable import EsperSim

extension Stage {
    /// The court as it was before its blocks went up and back to the wall and the backboards
    /// took boxes: floating two-by-two blocks 80 to 100 up, two cells off the wall, the gap a
    /// body climbs. For what that shape exercises: the ledge grab at a block's corner, the climb.
    static var formerCourt: Stage {
        let saved = (Stage.courtBlockShift, Stage.courtRimDrop, Stage.courtRimDepth)
        Stage.courtBlockShift = (0, 0)
        Stage.courtRimDrop = 6
        Stage.courtRimDepth = 0
        defer { (Stage.courtBlockShift, Stage.courtRimDrop, Stage.courtRimDepth) = saved }
        var stage = Stage.court
        stage.fill(.empty, columns: 1...2, rows: 8...9)
        stage.fill(.empty, columns: 31...32, rows: 8...9)
        stage.fixedExtras = []
        stage.extras = []
        stage.outOfReach = []
        return stage
    }
}
