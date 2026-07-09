# config/routes.rb
Rails.application.routes.draw do
  # Frontend Root (Points to GamesController outside of the Api namespace)
  root 'games#show'

  # Backend API (Points to Api::GamesController inside app/controllers/api/)
  namespace :api do
    resources :games, only: [:create, :show] do
      member do
        post :move
      end
    end
  end
end