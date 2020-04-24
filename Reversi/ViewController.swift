import UIKit

class ViewController: UIViewController {
    @IBOutlet private var boardView: BoardView!
    
    @IBOutlet private var messageDiskView: DiskView!
    @IBOutlet private var messageLabel: UILabel!
    @IBOutlet private var messageDiskSizeConstraint: NSLayoutConstraint!
    /// Storyboard 上で設定されたサイズを保管します。
    /// 引き分けの際は `messageDiskView` の表示が必要ないため、
    /// `messageDiskSizeConstraint.constant` を `0` に設定します。
    /// その後、新しいゲームが開始されたときに `messageDiskSize` を
    /// 元のサイズで表示する必要があり、
    /// その際に `messageDiskSize` に保管された値を使います。
    private var messageDiskSize: CGFloat!

    @IBOutlet private var playerControls: [UISegmentedControl]!
    var player1Control: UISegmentedControl {playerControls[0]}
    var player2Control: UISegmentedControl {playerControls[1]}
    @IBOutlet private var countLabels: [UILabel]!
    var darkCountLabel: UILabel {countLabels[0]}
    var lightCountLabel: UILabel {countLabels[1]}
    @IBOutlet private var playerActivityIndicators: [UIActivityIndicatorView]!
    var player1ActivityIndicator: UIActivityIndicatorView {playerActivityIndicators[0]}
    var player2ActivityIndicator: UIActivityIndicatorView {playerActivityIndicators[1]}
    var currentPlayerActivityIndicator: UIActivityIndicatorView? {
        switch gameState.turn {
        case .dark?: return player1ActivityIndicator
        case .light?: return player2ActivityIndicator
        case nil: return nil
        }
    }

    // 状態を変えるイベントは， gameState.boardを変えつつ，boardViewを変える，という1 input 2 outpusをする必要がある (setDisk)
    // boardViewでstateにアクセスするところは，gameStateとの同期だけにしたい
    private var gameState: GameState = .init(turn: nil, player1: .manual, player2: .manual, board: [[]]) { // ... IBOutlet ....
        didSet {
            try? saveGame()

            // 逆方向のbindあり
            player1Control.selectedSegmentIndex = gameState.player1.rawValue
            player2Control.selectedSegmentIndex = gameState.player2.rawValue

            // state -> UI
            updateCountLabels()
            updateMessageViews()
        }
    }
    
    private var animationCanceller: Canceller?
    private var isAnimating: Bool { animationCanceller != nil }
    
    private var playerCancellers: [Disk: Canceller] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        boardView.delegate = self
        messageDiskSize = messageDiskSizeConstraint.constant
        
        do {
            try loadGame()
        } catch _ {
            newGame()
        }
    }
    
    private var viewHasAppeared: Bool = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if viewHasAppeared { return }
        viewHasAppeared = true
        waitForPlayer()
    }
}

// MARK: Reversi logics

extension ViewController {

    /// `x`, `y` で指定されたセルに `disk` を置きます。
    /// - Parameter x: セルの列です。
    /// - Parameter y: セルの行です。
    /// - Parameter isAnimated: ディスクを置いたりひっくり返したりするアニメーションを表示するかどうかを指定します。
    /// - Parameter completion: アニメーション完了時に実行されるクロージャです。
    ///     このクロージャは値を返さず、アニメーションが完了したかを示す真偽値を受け取ります。
    ///     もし `animated` が `false` の場合、このクロージャは次の run loop サイクルの初めに実行されます。
    /// - Throws: もし `disk` を `x`, `y` で指定されるセルに置けない場合、 `DiskPlacementError` を `throw` します。
    func placeDisk(_ disk: Disk, atX x: Int, y: Int, animated isAnimated: Bool, completion: ((Bool) -> Void)? = nil) throws {
        let diskCoordinates = gameState.flippedDiskCoordinatesByPlacingDisk(disk, atX: x, y: y)
        if diskCoordinates.isEmpty {
            throw DiskPlacementError(disk: disk, x: x, y: y)
        }

        let completion: ((Bool) -> Void) = {
            self.gameState = GameState(turn: self.gameState.turn, player1: self.gameState.player1, player2: self.gameState.player2, boardView: self.boardView)
            completion?($0)
        }
        
        if isAnimated {
            let cleanUp: () -> Void = { [weak self] in
                self?.animationCanceller = nil
            }
            animationCanceller = Canceller(cleanUp)
            animateSettingDisks(at: [(x, y)] + diskCoordinates, to: disk) { [weak self] isFinished in
                guard let self = self else { return }
                guard let canceller = self.animationCanceller else { return }
                if canceller.isCancelled { return }
                cleanUp()

                // このcompletionは呼ばれないことがあってもいいのか？？意図的？
                completion(isFinished)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.boardView.setDisk(disk, atX: x, y: y, animated: false)
                for (x, y) in diskCoordinates {
                    self.boardView.setDisk(disk, atX: x, y: y, animated: false)
                }
                completion(true)
            }
        }
    }
    
    /// `coordinates` で指定されたセルに、アニメーションしながら順番に `disk` を置く。
    /// `coordinates` から先頭の座標を取得してそのセルに `disk` を置き、
    /// 残りの座標についてこのメソッドを再帰呼び出しすることで処理が行われる。
    /// すべてのセルに `disk` が置けたら `completion` ハンドラーが呼び出される。
    private func animateSettingDisks<C: Collection>(at coordinates: C, to disk: Disk, completion: @escaping (Bool) -> Void)
        where C.Element == (Int, Int)
    {
        guard let (x, y) = coordinates.first else {
            completion(true)
            return
        }
        
        let animationCanceller = self.animationCanceller!
        boardView.setDisk(disk, atX: x, y: y, animated: true) { [weak self] isFinished in
            guard let self = self else { return }
            if animationCanceller.isCancelled { return }
            if isFinished {
                self.animateSettingDisks(at: coordinates.dropFirst(), to: disk, completion: completion)
            } else {
                for (x, y) in coordinates {
                    self.boardView.setDisk(disk, atX: x, y: y, animated: false)
                }
                completion(false)
            }
        }
    }
}

// MARK: Game management

extension ViewController {
    /// ゲームの状態を初期化し、新しいゲームを開始します。
    func newGame() {
        boardView.reset()
        self.gameState = GameState(boardView: boardView)
    }
    
    /// プレイヤーの行動を待ちます。
    func waitForPlayer() {
        switch gameState.currentPlayer {
        case .manual?:
            break
        case .computer?:
            playTurnOfComputer()
        case nil:
            break
        }
    }
    
    /// プレイヤーの行動後、そのプレイヤーのターンを終了して次のターンを開始します。
    /// もし、次のプレイヤーに有効な手が存在しない場合、パスとなります。
    /// 両プレイヤーに有効な手がない場合、ゲームの勝敗を表示します。
    func nextTurn() {
        guard var turn = gameState.turn else { return }

        turn.flip()
        
        if gameState.validMoves(for: turn).isEmpty {
            if gameState.validMoves(for: turn.flipped).isEmpty {
                self.gameState.turn = nil
            } else {
                self.gameState.turn = turn
                
                let alertController = UIAlertController(
                    title: "Pass",
                    message: "Cannot place a disk.",
                    preferredStyle: .alert
                )
                alertController.addAction(UIAlertAction(title: "Dismiss", style: .default) { [weak self] _ in
                    self?.nextTurn()
                })
                present(alertController, animated: true)
            }
        } else {
            self.gameState.turn = turn
            waitForPlayer()
        }
    }
    
    /// "Computer" が選択されている場合のプレイヤーの行動を決定します。
    func playTurnOfComputer() {
        guard let turn = self.gameState.turn else { preconditionFailure() }
        let (x, y) = gameState.validMoves(for: turn).randomElement()!

        let currentPlayerActivityIndicator = self.currentPlayerActivityIndicator
        currentPlayerActivityIndicator?.startAnimating()
        
        let cleanUp: () -> Void = { [weak self] in
            guard let self = self else { return }
            currentPlayerActivityIndicator?.stopAnimating()
            self.playerCancellers[turn] = nil
        }
        let canceller = Canceller(cleanUp)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if canceller.isCancelled { return }
            cleanUp()
            
            try! self.placeDisk(turn, atX: x, y: y, animated: true) { [weak self] _ in
                self?.nextTurn()
            }
        }
        
        playerCancellers[turn] = canceller
    }
}

// MARK: Views

extension ViewController {
    /// 各プレイヤーの獲得したディスクの枚数を表示します。
    func updateCountLabels() {
        darkCountLabel.text = String(gameState.countDisks(of: .dark))
        lightCountLabel.text = String(gameState.countDisks(of: .light))
    }
    
    /// 現在の状況に応じてメッセージを表示します。
    func updateMessageViews() {
        switch gameState.turn {
        case .some(let side):
            messageDiskSizeConstraint.constant = messageDiskSize
            messageDiskView.disk = side
            messageLabel.text = "'s turn"
        case .none:
            if let winner = gameState.sideWithMoreDisks() {
                messageDiskSizeConstraint.constant = messageDiskSize
                messageDiskView.disk = winner
                messageLabel.text = " won"
            } else {
                messageDiskSizeConstraint.constant = 0
                messageLabel.text = "Tied"
            }
        }
    }
}

// MARK: Inputs

extension ViewController {
    /// リセットボタンが押された場合に呼ばれるハンドラーです。
    /// アラートを表示して、ゲームを初期化して良いか確認し、
    /// "OK" が選択された場合ゲームを初期化します。
    @IBAction func pressResetButton(_ sender: UIButton) {
        let alertController = UIAlertController(
            title: "Confirmation",
            message: "Do you really want to reset the game?",
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in })
        alertController.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self = self else { return }
            
            self.animationCanceller?.cancel()
            self.animationCanceller = nil
            
            for side in Disk.sides {
                self.playerCancellers[side]?.cancel()
                self.playerCancellers.removeValue(forKey: side)
            }
            
            self.newGame()
            self.waitForPlayer()
        })
        present(alertController, animated: true)
    }
    
    /// プレイヤーのモードが変更された場合に呼ばれるハンドラーです。
    @IBAction func changePlayerControlSegment(_ sender: UISegmentedControl) {
        switch sender {
        case player1Control:
            playerCancellers[Disk.sides[0]]?.cancel()
            gameState.player1 = Player(rawValue: sender.selectedSegmentIndex)!

            // state変更だけじゃなくて，このアクション起因で実行したいことがあるようだ
            if !isAnimating, gameState.turn == Disk.sides[0], case .computer? = gameState.currentPlayer {
                playTurnOfComputer()
            }
        case player2Control:
            playerCancellers[Disk.sides[1]]?.cancel()
            gameState.player2 = Player(rawValue: sender.selectedSegmentIndex)!

            // state変更だけじゃなくて，このアクション起因で実行したいことがあるようだ
            if !isAnimating, gameState.turn == Disk.sides[1], case .computer? = gameState.currentPlayer {
                playTurnOfComputer()
            }
        default:
            break
        }
    }
}

extension ViewController: BoardViewDelegate {
    /// `boardView` の `x`, `y` で指定されるセルがタップされたときに呼ばれます。
    /// - Parameter boardView: セルをタップされた `BoardView` インスタンスです。
    /// - Parameter x: セルの列です。
    /// - Parameter y: セルの行です。
    func boardView(_ boardView: BoardView, didSelectCellAtX x: Int, y: Int) {
        if isAnimating { return }

        // turnとplayerがセットである疑惑がある...
        switch gameState.currentPlayer {
        case .manual?:
            guard let turn = gameState.turn else { return } //
            // try? because doing nothing when an error occurs
            try? placeDisk(turn, atX: x, y: y, animated: true) { [weak self] _ in
                self?.nextTurn()
            }
        case .computer?, nil:
            break
        }
    }
}

// MARK: Save and Load


extension ViewController {
    private var path: String {
        (NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first! as NSString).appendingPathComponent("Game")
    }
    
    /// ゲームの状態をファイルに書き出し、保存します。
    func saveGame() throws {
        try gameState.save(to: path)
    }
    
    /// ゲームの状態をファイルから読み込み、復元します。
    func loadGame() throws {
        do {
            let s = try GameState(from: path)
            guard s.turn != nil else { throw GameState.FileIOError.read(path: path, cause: nil) }

            guard s.board.count == boardView.height,
                (s.board.allSatisfy {$0.count == boardView.width}) else { throw GameState.FileIOError.read(path: path, cause: nil) }
            self.gameState = s
            s.board.enumerated().forEach { y, row in
                row.enumerated().forEach { x, disk in
                    boardView.setDisk(disk, atX: x, y: y, animated: false)
                }
            }
        }
    }
}

// MARK: Additional types

final class Canceller {
    private(set) var isCancelled: Bool = false
    private let body: (() -> Void)?
    
    init(_ body: (() -> Void)?) {
        self.body = body
    }
    
    func cancel() {
        if isCancelled { return }
        isCancelled = true
        body?()
    }
}

struct DiskPlacementError: Error {
    let disk: Disk
    let x: Int
    let y: Int
}
