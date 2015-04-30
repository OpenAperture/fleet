defmodule OpenAperture.Fleet.FleetApiInstances.Tests do
  use ExUnit.Case
  alias OpenAperture.Fleet.FleetApiInstances

  test "caches pid" do
  	pid1 = FleetApiInstances.get_instance("my_token")
  	pid2 = FleetApiInstances.get_instance("my_token")
  	assert pid1 == pid2
  end
end