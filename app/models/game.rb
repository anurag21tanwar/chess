# app/models/game.rb
class Game < ApplicationRecord
  before_validation :initialize_game, on: :create

  validates :status, inclusion: { in: %w[active won draw] }
  validates :turn, inclusion: { in: %w[W B] }

  # Initialize a standard 8x8 board with only pawns
  def initialize_game
    return if board.present?

    # Row 0-7, Col 0-7. 
    # Row 1 is Black pawns, Row 6 is White pawns.
    new_board = Array.new(8) { Array.new(8, nil) }
    new_board[1] = Array.new(8, 'B')
    new_board[6] = Array.new(8, 'W')

    self.board = new_board
    self.turn = 'W' # White traditionally moves first
    self.status = 'active'
    self.user_color ||= 'W'
    self.computer_color = (user_color == 'W' ? 'B' : 'W')
  end

  # ==========================================
  # PRIORITY: Move and Kill Methods
  # ==========================================

  def player_move(from_r, from_c, to_r, to_c)
    return false, "Game is already over." unless status == 'active'

    legal_moves = get_legal_moves_for_cell(from_r, from_c)
    unless legal_moves.include?([to_r, to_c])
      return false, "Invalid move according to Pawn-only rules."
    end

    execute_move(from_r, from_c, to_r, to_c)
    process_turn_end

    return true, "Move executed successfully."
  end

  # Generates legal moves for a specific pawn
  def get_legal_moves_for_cell(r, c)
    piece = board[r][c]
    return [] if piece != turn

    moves = []
    direction = (piece == 'W') ? -1 : 1 # White moves up (-1), Black moves down (+1)

    # 1. Forward Move (1 step)
    next_r = r + direction
    if next_r.between?(0, 7) && board[next_r][c].nil?
      moves << [next_r, c]
    end

    # 2. Diagonal Captures (Kill)
    opponent = (piece == 'W') ? 'B' : 'W'
    [-1, 1].each do |dc|
      next_c = c + dc
      if next_r.between?(0, 7) && next_c.between?(0, 7)
        if board[next_r][next_c] == opponent
          moves << [next_r, next_c]
        end
      end
    end

    moves
  end

  # Gathers all legal moves available for the active player
  def all_legal_moves(player_color)
    moves = []
    (0..7).each do |r|
      (0..7).each do |c|
        if board[r][c] == player_color
          get_legal_moves_for_cell(r, c).each do |to_r, to_c|
            moves << { from: [r, c], to: [to_r, to_c] }
          end
        end
      end
    end
    moves
  end

  # ==========================================
  # PRIORITY: System Pawn Algorithm (AI)
  # ==========================================

  def make_computer_move
    return unless status == 'active' && turn == computer_color

    moves = all_legal_moves(computer_color)
    return if moves.empty? # Handled by draw condition check, but safe guard

    # AI Priority Logic: 
    # 1. Capture if possible. 2. Otherwise, pick a random legal forward move.
    captures = moves.select { |m| !board[m[:to][0]][m[:to][1]].nil? }
    selected_move = captures.any? ? captures.sample : moves.sample

    execute_move(selected_move[:from][0], selected_move[:from][1], selected_move[:to][0], selected_move[:to][1])
    process_turn_end
  end

  private

  def execute_move(from_r, from_c, to_r, to_c)
    # Create a fresh deep copy of the matrix so Rails detects the attribute change
    updated_board = board.map(&:dup)

    updated_board[to_r][to_c] = updated_board[from_r][from_c]
    updated_board[from_r][from_c] = nil

    # Explicitly assign the new array object to trigger Rails dirty tracking
    self.board = updated_board
  end

  # app/models/game.rb

  def process_turn_end
    if check_win_conditions
      # status and winner updated inside check_win_conditions
    elsif check_draw_conditions
      self.status = 'draw'
    else
      # Switch Turns only if the game is still active
      self.turn = (turn == 'W' ? 'B' : 'W')
    end
    save!
  end

  # ==========================================
  # PRIORITY: Win and Draw Methods
  # ==========================================

  def check_win_conditions
    # Condition 1: A pawn reaches the furthest row
    # White wins if any 'W' reaches Row 0. Black wins if any 'B' reaches Row 7.
    if board[0].include?('W')
      self.status = 'won'
      self.winner = 'W'
      return true
    elsif board[7].include?('B')
      self.status = 'won'
      self.winner = 'B'
      return true
    end

    # Condition 2: All opponent pieces are captured
    flattened = board.flatten
    unless flattened.include?('B')
      self.status = 'won'
      self.winner = 'W'
      return true
    end
    unless flattened.include?('W')
      self.status = 'won'
      self.winner = 'B'
      return true
    end

    false
  end

  def check_draw_conditions
    # Determine who is about to move next
    next_player = (turn == 'W' ? 'B' : 'W')

    # Temporary flip turn state just to calculate their legal moves accurately
    current_turn_state = self.turn
    self.turn = next_player

    moves = all_legal_moves(next_player)

    # Restore original turn state
    self.turn = current_turn_state

    moves.empty?
  end
end