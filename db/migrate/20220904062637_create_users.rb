class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users, id: false, force: :cascade do |t|
      t.string   :id, limit: 36, null: false, primary_key: true
      t.string :name
      t.text :address
      t.integer :score

      t.timestamps
    end
  end
end
