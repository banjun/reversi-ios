import Foundation

struct GameState {
    /// どちらの色のプレイヤーのターンかを表します。ゲーム終了時は `nil` です。
    var turn: Disk?
    var player1: Player
    var player2: Player
    var board: [[Disk?]] // 8x8を仮定している...
}

enum Player: Int {
    case manual = 0
    case computer = 1
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

    /// `x`, `y` で指定されたセルの状態を返します。
    /// セルにディスクが置かれていない場合、 `nil` が返されます。
    /// - Parameter x: セルの列です。
    /// - Parameter y: セルの行です。
    /// - Returns: セルにディスクが置かれている場合はそのディスクの値を、置かれていない場合は `nil` を返します。
    func diskAt(x: Int, y: Int) -> Disk? {
        guard case 0..<board.count = y, case 0..<board[y].count = x else { return nil }
        return board[y][x]
    }

    /// `side` で指定された色のディスクが盤上に置かれている枚数を返します。
    /// - Parameter side: 数えるディスクの色です。
    /// - Returns: `side` で指定された色のディスクの、盤上の枚数です。
    func countDisks(of side: Disk) -> Int {
        board.flatMap {$0}.reduce(into: 0) {$0 += $1 == side ? 1 : 0}
    }

    /// 盤上に置かれたディスクの枚数が多い方の色を返します。
    /// 引き分けの場合は `nil` が返されます。
    /// - Returns: 盤上に置かれたディスクの枚数が多い方の色です。引き分けの場合は `nil` を返します。
    func sideWithMoreDisks() -> Disk? {
        let darkCount = countDisks(of: .dark)
        let lightCount = countDisks(of: .light)
        if darkCount == lightCount {
            return nil
        } else {
            return darkCount > lightCount ? .dark : .light
        }
    }


    func flippedDiskCoordinatesByPlacingDisk(_ disk: Disk, atX x: Int, y: Int) -> [(Int, Int)] {
        let directions = [
            (x: -1, y: -1),
            (x:  0, y: -1),
            (x:  1, y: -1),
            (x:  1, y:  0),
            (x:  1, y:  1),
            (x:  0, y:  1),
            (x: -1, y:  0),
            (x: -1, y:  1),
        ]

        guard diskAt(x: x, y: y) == nil else {
            return []
        }

        var diskCoordinates: [(Int, Int)] = []

        for direction in directions {
            var x = x
            var y = y

            var diskCoordinatesInLine: [(Int, Int)] = []
            flipping: while true {
                x += direction.x
                y += direction.y

                switch (disk, diskAt(x: x, y: y)) { // Uses tuples to make patterns exhaustive
                case (.dark, .some(.dark)), (.light, .some(.light)):
                    diskCoordinates.append(contentsOf: diskCoordinatesInLine)
                    break flipping
                case (.dark, .some(.light)), (.light, .some(.dark)):
                    diskCoordinatesInLine.append((x, y))
                case (_, .none):
                    break flipping
                }
            }
        }

        return diskCoordinates
    }

    /// `x`, `y` で指定されたセルに、 `disk` が置けるかを調べます。
    /// ディスクを置くためには、少なくとも 1 枚のディスクをひっくり返せる必要があります。
    /// - Parameter x: セルの列です。
    /// - Parameter y: セルの行です。
    /// - Returns: 指定されたセルに `disk` を置ける場合は `true` を、置けない場合は `false` を返します。
    func canPlaceDisk(_ disk: Disk, atX x: Int, y: Int) -> Bool {
        !flippedDiskCoordinatesByPlacingDisk(disk, atX: x, y: y).isEmpty
    }

    /// `side` で指定された色のディスクを置ける盤上のセルの座標をすべて返します。
    /// - Returns: `side` で指定された色のディスクを置ける盤上のすべてのセルの座標の配列です。
    func validMoves(for side: Disk) -> [(x: Int, y: Int)] {
        (0..<board.count).flatMap {y in (0..<board[y].count).map {($0, y)}}
            .filter {canPlaceDisk(side, atX: $0, y: $1)}
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
            NSLog("%@", serialized) // ターンを変えるときとdiskを置いたときに呼ばれて，実は整合性がない可能性がある
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
