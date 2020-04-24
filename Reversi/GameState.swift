import Foundation

struct GameState {
    /// どちらの色のプレイヤーのターンかを表します。ゲーム終了時は `nil` です。
    var turn: Disk?
    var player1: Player
    var player2: Player
    var board: [[Disk?]] // 8x8を仮定している...
}

extension GameState {
    init(turn: Disk? = .dark, player1: Player = .manual, player2: Player = .manual, boardView: BoardView) {
        self.init(
            turn: turn,
            player1: player1,
            player2: player2,
            board: boardView.yRange.map {y in boardView.xRange.map {x in boardView.diskAt(x: x, y: y)}})
    }
}

extension GameState {
    var currentPlayer: Player? {
        switch turn {
        case .dark?: return player1
        case .light?: return player2
        case nil: return nil
        }
    }
}

extension GameState {
    enum FileIOError: Error {
        case write(path: String, cause: Error?)
        case read(path: String, cause: Error?)
    }

    init(from path: String) throws {
        do {
            try self.init(try String(contentsOfFile: path, encoding: .utf8))
        } catch _ {
            throw FileIOError.read(path: path, cause: nil)
        }
    }

    init(_ serialized: String) throws {
        let lines = serialized.split(separator: "\n").map {String($0)}
        let boardLines = lines.dropFirst()

        guard let header = lines.first.map([Character].init) else { throw FileIOError.read(path: "", cause: nil) }
        guard header.count >= 3 else { throw FileIOError.read(path: "", cause: nil) }

        self.turn = Disk?(symbol: String(header[0])).flatMap {$0}
        guard let player1 = (Int(String(header[1])).flatMap {Player(rawValue: $0)}),
            let player2 = (Int(String(header[2])).flatMap {Player(rawValue: $0)}) else { throw FileIOError.read(path: "", cause: nil) }
        self.player1 = player1
        self.player2 = player2
        self.board = boardLines.map {
            $0.map {Disk?(symbol: String($0)).flatMap {$0}}
        }
    }

    var serialized: String {
        ([[turn.symbol, player1.rawValue.description, player2.rawValue.description].joined()]
            + board.map {$0.map {$0.symbol}.joined()})
            .joined(separator: "\n")
    }

    func save(to path: String) throws {
        do {
            try serialized.write(toFile: path, atomically: true, encoding: .utf8)
        } catch let error {
            throw FileIOError.read(path: path, cause: error)
        }
    }
}

extension Optional where Wrapped == Disk {
    fileprivate init?<S: StringProtocol>(symbol: S) {
        switch symbol {
        case "x":
            self = .some(.dark)
        case "o":
            self = .some(.light)
        case "-":
            self = .none
        default:
            return nil
        }
    }

    fileprivate var symbol: String {
        switch self {
        case .some(.dark):
            return "x"
        case .some(.light):
            return "o"
        case .none:
            return "-"
        }
    }
}
