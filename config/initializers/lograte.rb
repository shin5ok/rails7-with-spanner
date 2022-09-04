Rails.application.configure do
    config.lograge.formatter = Lograge::Formatters::Json.new
end
