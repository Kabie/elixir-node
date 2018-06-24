defmodule Aehttpserver.Web.NotificationChannel do
  @moduledoc """
  Contains websocket topic validation
  """

  use Phoenix.Channel

  require Logger

  def join("room:notifications", _message, socket) do
    {:ok, socket}
  end

  def join("room:" <> _private_subtopic, _message, _socket) do
    {:error, %{reason: "unauthorized"}}
  end
end
