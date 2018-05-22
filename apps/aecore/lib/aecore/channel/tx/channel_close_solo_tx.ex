defmodule Aecore.Channel.Tx.ChannelCloseSoloTx do
  @moduledoc """
  Aecore structure of ChannelCloseSoloTx transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  alias Aecore.Channel.Tx.ChannelCloseSoloTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.ChainState
  alias Aecore.Channel.ChannelStateOnChain
  alias Aecore.Channel.ChannelStateOffChain
  alias Aecore.Channel.Worker, as: Channel

  require Logger

  @typedoc "Expected structure for the ChannelCloseSolo Transaction"
  @type payload :: %{
          state: map()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: Channel.channels_onchain()

  @typedoc "Structure of the ChannelCloseSoloTx Transaction type"
  @type t :: %ChannelCloseSoloTx{
          state: ChannelStateOffChain.t()
        }

  @doc """
  Definition of Aecore ChannelCloseSoloTx structure

  ## Parameters
  - state - the state to start close operation with
  """
  defstruct [:state]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: ChannelCloseSoloTx.t()
  def init(%{state: state} = _payload) do
    %ChannelCloseSoloTx{state: ChannelStateOffChain.init(state)}
  end

  @spec create(ChannelStateOffChain.t()) :: ChannelCloseSoloTx.t()
  def create(state) do
    %ChannelCloseSoloTx{state: state}
  end

  @spec sequence(ChannelCloseSoloTx.t()) :: non_neg_integer()
  def sequence(%ChannelCloseSoloTx{state: state}) do
    ChannelStateOffChain.sequence(state)
  end

  @spec channel_id(ChannelCloseSoloTx.t()) :: binary()
  def channel_id(%ChannelCloseSoloTx{state: state}) do
    ChannelStateOffChain.id(state)
  end

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelCloseSoloTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelCloseSoloTx{}, data_tx) do
    senders = DataTx.senders(data_tx)

    if length(senders) != 1 do
      {:error, "Invalid senders size"}
    else
      :ok
    end
  end

  @doc """
  Performs channel slash
  """
  @spec process_chainstate(
          ChainState.account(),
          ChannelStateOnChain.channels(),
          non_neg_integer(),
          ChannelCloseSoloTx.t(),
          DataTx.t()
        ) :: {:ok, {ChainState.accounts(), ChannelStateOnChain.t()}}
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelCloseSoloTx{state: state},
        _data_tx
      ) do
    channel_id = ChannelStateOffChain.id(state)

    new_channels =
      Map.update!(channels, channel_id, fn channel ->
        ChannelStateOnChain.apply_slashing(channel, block_height, state)
      end)

    {:ok, {accounts, new_channels}}
  end

  @doc """
  Checks whether all the data is valid according to the ChannelSoloCloseTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          ChainState.account(),
          ChannelStateOnChain.channels(),
          non_neg_integer(),
          ChannelCloseSoloTx.t(),
          DataTx.t()
        ) :: :ok
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelCloseSoloTx{state: state},
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

    channel_id = ChannelStateOffChain.id(state)
    channel = Map.get(channels, channel_id)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "Negative sender balance"}

      channel == nil ->
        {:error, "Channel doesn't exist (already closed?)"}

      !ChannelStateOnChain.active?(channel) ->
        {:error, "Can't solo close active channel. Use slash."}

      sender != ChannelStateOnChain.initiator_pubkey(channel) &&
          sender != ChannelStateOnChain.responder_pubkey(channel) ->
        {:error, "Sender must be a party of the channel"}

      true ->
        ChannelStateOnChain.validate_slashing(channel, state)
    end
  end

  @spec deduct_fee(
          ChainState.accounts(),
          non_neg_integer(),
          ChannelCreateTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: ChainState.account()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end
end