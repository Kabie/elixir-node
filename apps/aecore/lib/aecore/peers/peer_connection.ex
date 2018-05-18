defmodule Aecore.Peers.PeerConnection do
  use GenServer

  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.Worker.Supervisor
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Tx.SignedTx

  require Logger

  @behaviour :ranch_protocol

  @p2p_protocol_vsn 2
  @noise_timeout 5000

  @p2p_response 100
  @ping 1
  @get_header_by_hash 3
  @get_header_by_height 15
  @header 4
  @get_n_successors 5
  @header_hashes 6
  @get_block 7
  @block 11
  @tx 9
  @get_mempool 13
  @mempool 14

  def start_link(ref, socket, transport, opts) do
    IO.inspect("Another start link called")
    args = [ref, socket, transport, opts]
    {:ok, pid} = :proc_lib.start_link(__MODULE__, :accept_init, args)
    {:ok, pid}
  end

  def start_link(conn_info) do
    IO.inspect "PeerConnection is called"
    IO.inspect conn_info
    GenServer.start_link(__MODULE__, conn_info)
  end

  def accept_init(ref, socket, :ranch_tcp, opts) do
    IO.inspect "Accept init"
    :ok = :proc_lib.init_ack({:ok, self()})
    {:ok, {host, _}} = :inet.peername(socket)
    host_bin = host |> :inet.ntoa() |> :binary.list_to_bin()
    genesis_hash = Block.genesis_hash()
    version = <<@p2p_protocol_vsn::64>>

    state = Map.merge(opts, %{host: host_bin, version: version, genesis: genesis_hash})

    noise_opts = noise_opts(state.privkey, state.pubkey, genesis_hash, version)
    :ok = :ranch.accept_ack(ref)
    :ok = :ranch_tcp.setopts(socket, [{:active, true}])

    case :enoise.accept(socket, noise_opts) do
      {:ok, noise_socket, noise_state} ->
        r_pubkey = noise_state |> :enoise_hs_state.remote_keys() |> :enoise_keypair.pubkey()
        new_state = Map.merge(state, %{r_pubkey: r_pubkey, status: {:connected, noise_socket}})
        :gen_server.enter_loop(__MODULE__, [], new_state)

      {:error, _reason} ->
        :ranch_tcp.close(socket)
    end
  end

  def init(conn_info) do
    IO.inspect "Peer connection init"
    genesis_hash = Block.genesis_hash()

    updated_con_info =
      Map.merge(conn_info, %{
        version: <<@p2p_protocol_vsn::64>>,
        genesis: genesis_hash
      })

    # trigger a timeout so that a connection is attempted immediately
    {:ok, updated_con_info, 0}
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @spec get_header_by_hash(binary(), pid()) :: {:ok, Header.t()} | {:error, term()}
  def get_header_by_hash(hash, pid),
    do: send_request_msg(@get_header_by_hash, :erlang.term_to_binary(%{hash: hash}), pid)

  @spec get_header_by_height(non_neg_integer(), pid()) :: {:ok, Header.t()} | {:error, term()}
  def get_header_by_height(height, pid),
    do: send_request_msg(@get_header_by_height, :erlang.term_to_binary(%{height: height}), pid)

  @spec get_n_successors(binary(), non_neg_integer(), pid()) ::
          {:ok, list(Header.t())} | {:error, term()}
  def get_n_successors(hash, n, pid),
    do: send_request_msg(@get_n_successors, :erlang.term_to_binary(%{hash: hash, n: n}), pid)

  @spec get_block(binary(), pid()) :: {:ok, Block.t()} | {:error, term()}
  def get_block(hash, pid),
    do: send_request_msg(@get_block, :erlang.term_to_binary(%{hash: hash}), pid)

  @spec get_mempool(pid()) :: {:ok, %{binary() => SignedTx.t()}} | {:ok, %{}}
  def get_mempool(pid) when is_pid(pid),
    do: send_request_msg(@get_mempool, :erlang.term_to_binary(<<>>), pid)

  @spec send_new_block(Block.t(), pid()) :: :ok | :error
  def send_new_block(block, pid),
    do: send_msg_no_response(@block, :erlang.term_to_binary(%{block: block}), pid)

  @spec send_new_tx(SignedTx.t(), pid()) :: :ok | :error
  def send_new_tx(tx, pid), do: send_msg_no_response(@tx, :erlang.term_to_binary(%{tx: tx}), pid)

  def handle_call(
        {:send_request_msg, <<type::16, _::binary>> = msg},
        from,
        %{status: {:connected, socket}} = state
      ) do
    IO.inspect("#{__MODULE__}: bef send to enoise")
    :ok = :enoise.send(socket, msg)
    IO.inspect("#{__MODULE__}: after send to enoise")

    response_type =
      case type do
        @get_header_by_hash ->
          @header

        @get_header_by_height ->
          @header

        @get_n_successors ->
          @header_hashes

        @get_block ->
          @block

        @get_mempool ->
          @mempool
      end

    updated_state = Map.put(state, :requests, %{response_type => from})
    {:noreply, updated_state}
  end

  def handle_call({:send_msg_no_response, msg}, _from, %{status: {:connected, socket}} = state) do
    res = :enoise.send(socket, msg)
    IO.inspect("Handle call send_msg_no_response")
    {:reply, res, state}
  end

  def handle_call({:clear_request, type}, _from, state) do
    updated_state = state |> pop_in([:requests, type]) |> elem(1)
    {:reply, :ok, updated_state}
  end

  def handle_info(
        :timeout,
        %{
          genesis: genesis,
          version: version,
          pubkey: pubkey,
          privkey: privkey,
          r_pubkey: r_pubkey,
          host: host,
          port: port
        } = state
  ) do
    IO.inspect "Gen TCP connect"
    case :gen_tcp.connect(host, port, [:binary, reuseaddr: true, active: false]) do
      {:ok, socket} ->
        IO.inspect "Inside socket"
        noise_opts = noise_opts(privkey, pubkey, r_pubkey, genesis, version)

        :inet.setopts(socket, active: true)

        case :enoise.connect(socket, noise_opts) do
          {:ok, noise_socket, status} ->
            IO.inspect "Enoise connect"
            IO.inspect status

            new_state = Map.put(state, :status, {:connected, noise_socket})
            peer = %{host: host, pubkey: r_pubkey, port: port, connection: self()}
            :ok = ping(new_state)
            Peers.add_peer(peer)
            {:noreply, new_state}

          {:error, reason} ->
            IO.inspect ":enoise.connect ERROR: #{inspect(reason)}"
            :gen_tcp.close(socket)
            {:stop, :normal, state}
        end

      {:error, reason} ->
        IO.inspect ":get_tcp.connect ERROR: #{inspect(reason)}"
        {:stop, :normal, state}
    end
  end

  def handle_info({:noise, _, <<type::16, payload::binary()>>}, state) do
    deserialized_payload = :erlang.binary_to_term(payload)
    self = self()

    case type do
      @p2p_response ->
        spawn(fn -> handle_response(deserialized_payload, self, state.requests) end)

      @ping ->
        handle_ping(deserialized_payload, self, state)

      @get_header_by_hash ->
        spawn(fn -> handle_get_header_by_hash(deserialized_payload, self) end)

      @get_header_by_height ->
        spawn(fn -> handle_get_header_by_height(deserialized_payload, self) end)

      @get_n_successors ->
        spawn(fn -> handle_get_n_successors(deserialized_payload, self) end)

      @get_block ->
        spawn(fn -> handle_get_block(deserialized_payload, self) end)

      @get_mempool ->
        spawn(fn -> handle_get_mempool(self) end)

      @block ->
        spawn(fn -> handle_new_block(deserialized_payload) end)

      @tx ->
        spawn(fn -> handle_new_tx(deserialized_payload) end)
    end

    {:noreply, state}
  end

  def handle_info({:tcp_closed, _}, state) do
    Logger.info("Connection interrupted by peer - #{inspect(state)}")

    Peers.remove_peer(state.r_pubkey)
    {:stop, :normal, state}
  end

  defp ping(%{status: {:connected, socket}, genesis: genesis_hash}) do
    top_block = Chain.top_block()
    peers = Enum.map(Peers.all_peers(), fn peer -> Map.delete(peer, :connection) end)

    ping_object = %{
      genesis_hash: genesis_hash,
      best_hash: Chain.top_block_hash(),
      difficulty: top_block.header.target,
      share: 32,
      peers: peers,
      port: Supervisor.sync_port()
    }

    serialized_ping_object = :erlang.term_to_binary(ping_object)
    msg = <<@ping::16, serialized_ping_object::binary()>>
    :enoise.send(socket, msg)
  end

  defp send_response(result, type, pid) do
    payload =
      case result do
        {:ok, object} ->
          %{result: true, type: type, reason: nil, object: object}

        {:error, reason} ->
          %{result: false, type: type, reason: reason, object: nil}
      end

    send_msg_no_response(@p2p_response, :erlang.term_to_binary(payload), pid)
  end

  defp send_request_msg(id, payload, pid) do
    msg = <<id::16, payload::binary>>
    GenServer.call(pid, {:send_request_msg, msg})
  end

  defp send_msg_no_response(id, payload, pid) do
    msg = <<id::16, payload::binary>>
    IO.inspect(pid, label: "Send msg no response to pid:")
    GenServer.call(pid, {:send_msg_no_response, msg})
  end

  defp handle_ping(payload, conn_pid, %{host: host, r_pubkey: r_pubkey}) do
    # initial ping
    if !Peers.have_peer?(r_pubkey) do
      peer = %{pubkey: r_pubkey, port: payload.port, host: host, connection: conn_pid}
      Peers.add_peer(peer)
    else
      :ok
    end
  end

  defp handle_response(payload, parent, requests) do
    result = payload.result
    type = payload.type

    reply =
      case result do
        true ->
          IO.inspect("Payload object: #{inspect(payload.object)}")
          {:ok, payload.object}

        false ->
          {:error, payload.reason}
      end

    GenServer.reply(requests[type], reply)

    clear_request(parent, type)
  end

  defp clear_request(pid, type) do
    GenServer.call(pid, {:clear_request, type})
  end

  defp handle_get_header_by_hash(payload, pid) do
    hash = payload.hash
    IO.inspect hash
    result = Chain.get_header(hash)
    send_response(result, @header, pid)
  end

  defp handle_get_header_by_height(payload, pid) do
    height = payload.height
    result = Chain.get_header_by_height(height)
    send_response(result, @header, pid)
  end

  defp handle_get_n_successors(payload, pid) do
    starting_header = payload.hash
    count = payload.n

    result =
      case Chain.get_headers_forward(starting_header, count) do
        {:ok, headers} ->
          header_hashes =
            Enum.map(headers, fn header ->
              {header.height, BlockValidation.block_header_hash(header)}
            end)

          {:ok, Enum.reverse(header_hashes)}

        {:error, reason} ->
          {:error, reason}
      end

    IO.inspect(result)

    send_response(result, @header_hashes, pid)
  end

  defp handle_get_block(payload, pid) do
    hash = payload.hash
    result = Chain.get_block(hash)
    send_response(result, @block, pid)
  end

  defp handle_get_mempool(pid) do
    pool = Pool.get_pool()
    send_response({:ok, pool}, @mempool, pid)
  end

  defp handle_new_block(payload) do
    IO.inspect("New Block incomming")
    block = payload.block
    Chain.add_block(block)
  end

  defp handle_new_tx(payload) do
    tx = payload.tx
    Pool.add_transaction(tx)
  end

  defp noise_opts(privkey, pubkey, r_pubkey, genesis_hash, version) do
    opts = [
      noise: "Noise_XK_25519_ChaChaPoly_BLAKE2b",
      s: :enoise_keypair.new(:dh25519, privkey, pubkey),
      rs: :enoise_keypair.new(:dh25519, r_pubkey),
      prologue: <<version::binary(), genesis_hash::binary()>>,
      timeout: @noise_timeout
    ]
  #  IO.inspect "noise_opts"
  #  IO.inspect opts
  #  opts
  end

  defp noise_opts(privkey, pubkey, genesis_hash, version) do
    opts = [
      noise: "Noise_XK_25519_ChaChaPoly_BLAKE2b",
      s: :enoise_keypair.new(:dh25519, privkey, pubkey),
      prologue: <<version::binary(), genesis_hash::binary()>>,
      timeout: @noise_timeout
    ]
   # IO.inspect "noise_opts"
   # IO.inspect opts
   # opts
  end
end
