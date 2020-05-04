defmodule NojsChatTest do
  use ExUnit.Case
  doctest NojsChat

  test "greets the world" do
    assert NojsChat.hello() == :world
  end
end
