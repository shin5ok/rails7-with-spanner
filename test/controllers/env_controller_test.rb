require "test_helper"

class EnvControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get env_index_url
    assert_response :success
  end
end
