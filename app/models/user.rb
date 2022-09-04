class User < ApplicationRecord
    include IdGenerator
    def cached_entry(id)
        Rails.cache.fetch("#{id}", expires_in: 20.seconds) do
            User.find(id)
        end
    end
end
