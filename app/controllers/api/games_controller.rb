# app/controllers/api/games_controller.rb
module Api
  class GamesController < ApplicationController
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

      from_r = params[:from_r].to_i
      from_c = params[:from_c].to_i
      to_r   = params[:to_r].to_i
      to_c   = params[:to_c].to_i

      success, message = game.player_move(from_r, from_c, to_r, to_c)

      if success
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