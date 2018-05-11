defmodule Aecore.Peers.Events do
  @spec publish(atom(), any()) :: :ok
  def publish(event, info) do
    data = %{sender: self(), time: :os.timestamp(), info: info}
    :gproc_ps.publish(:l, event, data)
  end

  @spec subscribe(atom()) :: true
  def subscribe(event) do
    :grpoc_ps.subscribe(:l, event)
  end

  @spec unsubscribe(atom()) :: true
  def unsubscribe(event) do
    :gproc_ps.unsubscribe(:l, event)
  end
end
