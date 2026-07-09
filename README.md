# Pawn-Only Chess Game: Comprehensive Architecture & Implementation Guide

This document combines the structural design, algorithm logic, and the complete Ruby on Rails codebase for the Pawn-Only Chess variant.

---

## 1. Database Schema & Architecture Design

The persistence layer uses a minimalistic schema to record the game state, facilitating pause, resume, and restart functionalities.

### Migration Schema

```ruby
# db/migrate/XXXXXX_create_games.rb
class CreateGames < ActiveRecord::Migration[7.2]
  def change
    create_table :games do |t|
      t.json :board, null: false                 # 8x8 matrix representing the grid layout
      t.string :turn, null: false, default: 'W'  # Current active turn ('W' or 'B')
      t.string :status, null: false, default: 'active' # 'active', 'won', or 'draw'
      t.string :winner                           # 'W', 'B', or nil
      t.string :user_color, default: 'W'         # Player color assignment
      t.string :computer_color, default: 'B'     # System color assignment

      t.timestamps
    end
  end
end
```

### State Representation

The 8x8 chess matrix is tracked using an array of arrays within a single native JSON database column (`board`).

- Row 0 represents the top row of the board (Black's starting baseline).
- Row 7 represents the bottom row of the board (White's starting baseline).

### Initial Matrix Layout

```json
[
  [null, null, null, null, null, null, null, null],
  ["B",  "B",  "B",  "B",  "B",  "B",  "B",  "B" ],
  [null, null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null, null],
  [null, null, null, null, null, null, null, null],
  ["W",  "W",  "W",  "W",  "W",  "W",  "W",  "W" ],
  [null, null, null, null, null, null, null, null]
]
```

- Row 0 — Target win-condition for White
- Row 1 — Black pawns starting position
- Row 6 — White pawns starting position
- Row 7 — Target win-condition for Black

---

## 2. Core Game Engine Model

This handles move validation (`move_and_kill`), deep array cloning (to bypass Rails' nested array JSON dirty tracking limitation), automated system AI moves, and game-over conditions.

```ruby
# app/models/game.rb
class Game < ApplicationRecord
  before_validation :initialize_game, on: :create

  validates :status, inclusion: { in: %w[active won draw] }
  validates :turn, inclusion: { in: %w[W B] }

  # Automatically setup the matrix layout on game instantiation
  def initialize_game
    return if board.present?

    new_board = Array.new(8) { Array.new(8, nil) }
    new_board[1] = Array.new(8, 'B')
    new_board[6] = Array.new(8, 'W')

    self.board = new_board
    self.turn = 'W' # White traditionally moves first
    self.status = 'active'
    self.user_color ||= 'W'
    self.computer_color = (user_color == 'W' ? 'B' : 'W')
  end

  # Primary API wrapper interface to process a human move
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

  # Generates specific valid forward/diagonal options for an individual pawn
  def get_legal_moves_for_cell(r, c)
    piece = board[r][c]
    return [] if piece != turn

    moves = []
    direction = (piece == 'W') ? -1 : 1 # White moves up rows (-1), Black moves down rows (+1)

    # 1. Forward Move Step (Target cell must be empty)
    next_r = r + direction
    if next_r.between?(0, 7) && board[next_r][c].nil?
      moves << [next_r, c]
    end

    # 2. Diagonal Capture Step (Target cell must have an opponent piece)
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

  # Gathers every legal move available across all matching surviving pieces
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

  # System Pawn Algorithm (AI Player)
  def make_computer_move
    return unless status == 'active' && turn == computer_color

    moves = all_legal_moves(computer_color)
    return if moves.empty?

    # Tactical Priority Selection:
    # 1. Capture/Kill if available immediately
    # 2. Fall back to picking a random valid forward move
    captures = moves.select { |m| !board[m[:to][0]][m[:to][1]].nil? }
    selected_move = captures.any? ? captures.sample : moves.sample

    execute_move(selected_move[:from][0], selected_move[:from][1], selected_move[:to][0], selected_move[:to][1])
    process_turn_end
  end

  private

  def execute_move(from_r, from_c, to_r, to_c)
    # Deep copy needed so Rails registers internal array changes on native JSON columns
    updated_board = board.map(&:dup)
    updated_board[to_r][to_c] = updated_board[from_r][from_c]
    updated_board[from_r][from_c] = nil
    self.board = updated_board
  end

  def process_turn_end
    if check_win_conditions
      # State managed dynamically inside check_win_conditions
    elsif check_draw_conditions
      self.status = 'draw'
    else
      self.turn = (turn == 'W' ? 'B' : 'W')
    end
    save!
  end

  def check_win_conditions
    # Condition A: Reach the furthest terminal opposing baseline row
    if board[0].include?('W')
      self.status = 'won'; self.winner = 'W'; return true
    elsif board[7].include?('B')
      self.status = 'won'; self.winner = 'B'; return true
    end

    # Condition B: Total annihilation/Extermination of opposing pieces
    flattened = board.flatten
    unless flattened.include?('B')
      self.status = 'won'; self.winner = 'W'; return true
    end
    unless flattened.include?('W')
      self.status = 'won'; self.winner = 'B'; return true
    end

    false
  end

  def check_draw_conditions
    next_player = (turn == 'W' ? 'B' : 'W')

    # State simulation wrapper: Safely test opponent's valid moves without altering runtime turn logic premature
    current_turn_state = self.turn
    self.turn = next_player
    moves = all_legal_moves(next_player)
    self.turn = current_turn_state

    moves.empty?
  end
end
```

---

## 3. Web & API Routing Layout

Maps the browser navigation context to the web controller, alongside the encapsulated REST endpoints.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Mounts main view application directly to http://localhost:3000
  root 'games#show'

  namespace :api do
    resources :games, only: [:create, :show] do
      member do
        post :move
      end
    end
  end
end
```

---

## 4. Backend Controllers

### UI Layout Server Controller

```ruby
# app/controllers/games_controller.rb
class GamesController < ApplicationController
  def show
    # Renders the HTML template containing visual asset layout files
  end
end
```

### JSON Engine API Controller

```ruby
# app/controllers/api/games_controller.rb
module Api
  class GamesController < ApplicationController
    # Skips authenticity token lookup layer for explicit client API testing compatibility
    skip_before_action :verify_authenticity_token

    # POST /api/games
    def create
      user_color = params[:user_color] || 'W'
      game = Game.create!(user_color: user_color)
      render json: game, status: :created
    end

    # GET /api/games/:id
    def show
      game = Game.find(params[:id])
      render json: game
    end

    # POST /api/games/:id/move
    def move
      game = Game.find(params[:id])

      success, message = game.player_move(
        params[:from_r].to_i, params[:from_c].to_i,
        params[:to_r].to_i, params[:to_c].to_i
      )

      if success
        # Immediately chain system AI reply sequence synchronously if session remains ongoing
        if game.status == 'active' && game.turn == game.computer_color
          game.make_computer_move
        end
        render json: game, status: :ok
      else
        render json: { error: message }, status: :unprocessable_entity
      end
    end
  end
end
```

---

## 5. Frontend User Interface Template

A monolithic layout container combining grid-level inline styles, reactive browser elements, state updates, and standard asynchronous execution APIs.

```html
<div id="game-container" style="font-family: sans-serif; max-width: 500px; margin: 20px auto;">
  <h2>Pawn-Only Chess Engine</h2>

  <div style="margin-bottom: 15px;">
    <button onclick="createNewGame()">Start New Game</button>
    <span style="margin: 0 10px; color: #ccc;">|</span>
    <input type="number" id="resume-id-input" placeholder="Enter Game ID" style="width: 100px; padding: 3px;">
    <button onclick="resumeGame()">Resume Game</button>
  </div>

  <hr>
  <h3>Game ID: <span id="game-id">None</span></h3>
  <h4 id="turn-indicator">Turn: —</h4>
  <h4 id="status-indicator">Status: —</h4>

  <div id="chess-board" style="display: grid; grid-template-columns: repeat(8, 50px); grid-template-rows: repeat(8, 50px); width: 400px; height: 400px; border: 3px solid #333; margin-top: 20px;"></div>
</div>

<script>
  let currentGameId = null;
  let selectedSquare = null;
  let boardState = [];

  // Calls POST /api/games to create a fresh record instance
  async function createNewGame() {
    const res = await fetch('/api/games', { method: 'POST', headers: {'Content-Type': 'application/json'} });
    const data = await res.json();
    currentGameId = data.id;
    updateUI(data);
  }

  // Calls GET /api/games/:id to reload an existing database record (Pause/Resume functionality)
  async function resumeGame() {
    const gameId = document.getElementById('resume-id-input').value;
    if (!gameId) return alert("Please enter a Game ID.");

    const res = await fetch(`/api/games/${gameId}`);
    if (res.ok) {
      const data = await res.json();
      currentGameId = data.id;
      updateUI(data);
      document.getElementById('resume-id-input').value = '';
    } else {
      alert("Game archive ID matching that parameter not found.");
    }
  }

  function updateUI(game) {
    document.getElementById('game-id').innerText = game.id;
    document.getElementById('turn-indicator').innerText = `Turn: ${game.turn === 'W' ? 'White' : 'Black'}`;

    let statusText = `Status: ${game.status.toUpperCase()}`;
    if (game.winner) statusText += ` (Winner: ${game.winner === 'W' ? 'White' : 'Black'})`;
    document.getElementById('status-indicator').innerText = statusText;

    boardState = game.board;
    renderBoard();
  }

  function renderBoard() {
    const boardDiv = document.getElementById('chess-board');
    boardDiv.innerHTML = '';

    for (let r = 0; r < 8; r++) {
      for (let c = 0; c < 8; c++) {
        const square = document.createElement('div');
        square.style.width = '50px';
        square.style.height = '50px';
        square.style.display = 'flex';
        square.style.alignItems = 'center';
        square.style.justifyContent = 'center';
        square.style.fontSize = '26px';
        square.style.cursor = 'pointer';

        // Render block background based on selection context vs standard grid alternate styling
        if (selectedSquare && selectedSquare.r === r && selectedSquare.c === c) {
          square.style.backgroundColor = '#baca44'; // Selection Highlight
        } else {
          square.style.backgroundColor = (r + c) % 2 === 0 ? '#eeeed2' : '#769656';
        }

        const piece = boardState[r][c];
        if (piece === 'W') square.innerText = '♙';
        if (piece === 'B') square.innerText = '♟';

        square.onclick = () => handleSquareClick(r, c);
        boardDiv.appendChild(square);
      }
    }
  }

  async function handleSquareClick(r, c) {
    if (!currentGameId) return alert("Please start or resume a game session first.");

    if (!selectedSquare) {
      // Pick up a piece matching the current validation context
      if (boardState[r][c] !== null) {
        selectedSquare = { r, c };
        renderBoard();
      }
    } else {
      // Deselect if clicking the exact same cell twice
      if (selectedSquare.r === r && selectedSquare.c === c) {
        selectedSquare = null;
        renderBoard();
        return;
      }

      // Process target move transaction to endpoint
      const res = await fetch(`/api/games/${currentGameId}/move`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ from_r: selectedSquare.r, from_c: selectedSquare.c, to_r: r, to_c: c })
      });

      const data = await res.json();
      if (res.ok) {
        updateUI(data);
      } else {
        alert(data.error);
      }
      selectedSquare = null;
    }
  }
</script>
```
