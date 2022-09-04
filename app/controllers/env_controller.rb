class EnvController < ApplicationController
  def index
    render json: ENV
  end
end
