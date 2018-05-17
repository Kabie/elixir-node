defmodule Aecore.Channel.Tx.ChannelSettleTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  alias Aecore.Channel.Tx.ChannelSettleTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.ChainState
  alias Aecore.Channel.ChannelStateOnChain

  require Logger

  @typedoc "Expected structure for the ChannelSettle Transaction"
  @type payload :: %{
    channel_id: binary(),
  }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of SpendTx we don't have a subdomain chainstate."
  @type tx_type_state() :: %{}

  @typedoc "Structure of the ChannelSettle Transaction type"
  @type t :: %ChannelSettleTx{
    channel_id: binary(),
  }

  @doc """
  Definition of Aecore ChannelSettle structure

  ## Parameters
  - channel_id: channel id
  """
  defstruct [:channel_id]
  use ExConstructor

  @spec get_chain_state_name :: :channels
  def get_chain_state_name, do: :channels

  @spec init(payload()) :: SpendTx.t()
  def init(%{channel_id: channel_id} = _payload) do
    %ChannelSettleTx{channel_id: channel_id}
  end

  @doc """
  Checks transactions internal contents validity
  """
  @spec validate(ChannelSettleTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%ChannelSettleTx{} = tx, data_tx) do
    senders = DataTx.senders(data_tx)
    
    cond do
      length(senders) != 1 ->
        {:error, "Invalid from_accs size"}

      true ->
        :ok
    end
  end

  @doc """
  Changes the account state (balance) of both parties and creates channel object
  """
  @spec process_chainstate(
          ChainState.account(),
          ChannelStateOnChain.channels(),
          non_neg_integer(),
          ChannelSettleTx.t(),
          DataTx.t()) :: {:ok, {ChainState.accounts(), ChannelStateOnChain.t()}}
  def process_chainstate(
    accounts,
    channels,
    block_height,
    %ChannelSettleTx{channel_id: channel_id},
    _data_tx
  ) do
    channel = channels[channel_id]

    new_accounts =
      accounts
      |> AccountStateTree.update(channel.initiator_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, channel.initiator_amount)
      end)
      |> AccountStateTree.update(channel.responder_pubkey, fn acc ->
        Account.apply_transfer!(acc, block_height, channel.responder_amount)
      end)

    new_channels = Map.pop(channels, channel_id)

    {:ok, {new_accounts, new_channels}}
  end

  @doc """
  Checks whether all the data is valid according to the SpendTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          ChainState.account(),
          ChannelStateOnChain.channels(),
          non_neg_integer(),
          ChannelSettleTx.t(),
          DataTx.t()) 
  :: :ok
  def preprocess_check(
    accounts,
    channels,
    block_height,
    %ChannelSettleTx{channel_id: channel_id},
    data_tx
  ) do
    fee = DataTx.fee(data_tx)
    sender = DataTx.main_sender(data_tx)

    channel = Map.get(channels, channel_id)

    cond do
      AccountStateTree.get(accounts, sender).balance < 0 ->
        {:error, "Negative sender balance"}

      channel == nil ->
        {:error, "Channel doesn't exist (already closed?)"}

      ChannelStateOnChain.settled?(channel, block_height) ->
        {:error, "Channel isn't settled"}

      true ->
        :ok
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

end