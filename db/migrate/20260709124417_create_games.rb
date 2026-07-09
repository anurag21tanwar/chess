class CreateGames < ActiveRecord::Migration[7.2]
  def change
    create_table :games do |t|
      t.json :board
      t.string :turn
      t.string :status
      t.string :winner
      t.string :user_color
      t.string :computer_color

      t.timestamps
    end
  end
end
