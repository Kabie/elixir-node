defmodule Aecore.Account.Tx.SpendTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Account.Account
  alias Aecore.Wallet
  alias Aecore.Account.Account
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.Pool.Worker, as: Pool

  require Logger

  @typedoc "Expected structure for the Spend Transaction"
  @type payload :: %{
          receiver: Wallet.pubkey(),
          amount: non_neg_integer(),
          version: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of SpendTx we don't have a subdomain chainstate."
  @type tx_type_state() :: %{}

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %SpendTx{
          receiver: Wallet.pubkey(),
          amount: non_neg_integer(),
          version: non_neg_integer()
        }

  @doc """
  Definition of Aecore SpendTx structure

  ## Parameters
  - receiver: To account is the public address of the account receiving the transaction
  - amount: The amount of tokens send through the transaction
  - version: States whats the version of the Spend Transaction
  """
  defstruct [:receiver, :amount, :version]

  # Callbacks

  @callback get_chain_state_name :: atom() | nil
  def get_chain_state_name, do: nil

  @spec init(payload()) :: SpendTx.t()
  def init(%{receiver: receiver, amount: amount}) do
    %SpendTx{receiver: receiver, amount: amount, version: get_tx_version()}
  end

  @doc """
  Checks wether the amount that is send is not a negative number
  """
  @spec is_valid?(SpendTx.t(), DataTx.t()) :: boolean()
  def is_valid?(%SpendTx{} = tx, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      tx.amount < 0 ->
        Logger.error("The amount cannot be a negative number")
        false

      tx.version != get_tx_version() ->
        Logger.error("Invalid version")
        false

      length(senders) != 1 ->
        Logger.error("Invalid senders number")
        false

      true ->
        true
    end
  end

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          ChainState.account(),
          tx_type_state(),
          non_neg_integer(),
          SpendTx.t(),
          DataTx.t()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(accounts, %{}, _block_height, %SpendTx{} = tx, data_tx) do
    sender = DataTx.sender(data_tx)

    new_accounts =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.transaction_in!(acc, tx.amount * -1)
      end)
      |> AccountStateTree.update(tx.receiver, fn acc ->
        Account.transaction_in!(acc, tx.amount)
      end)

    {new_accounts, %{}}
  end

  @doc """
  Checks whether all the data is valid according to the SpendTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check!(
          ChainState.accounts(),
          tx_type_state(),
          non_neg_integer(),
          SpendTx.t(),
          DataTx.t()
        ) :: :ok
  def preprocess_check!(accounts, %{}, _block_height, tx, data_tx) do
    sender_state = AccountStateTree.get(accounts, DataTx.sender(data_tx))

    if sender_state.balance - (DataTx.fee(data_tx) + tx.amount) < 0 do
      throw({:error, "Negative balance"})
    else
      :ok
    end
  end

  @spec deduct_fee(ChainState.accounts(), SpendTx.t(), DataTx.t(), non_neg_integer()) ::
          ChainState.account()
  def deduct_fee(accounts, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, data_tx, fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t(), :miner | :pool | :validation) :: boolean()
  def is_minimum_fee_met?(tx, identifier) do
    if identifier == :validation do
      true
    else
      tx_size_bytes = Pool.get_tx_size_bytes(tx)

      bytes_per_token =
        case identifier do
          :pool ->
            Application.get_env(:aecore, :tx_data)[:pool_fee_bytes_per_token]

          :miner ->
            Application.get_env(:aecore, :tx_data)[:miner_fee_bytes_per_token]
        end

      tx.data.fee >= Float.floor(tx_size_bytes / bytes_per_token)
    end
  end

  def get_tx_version, do: Application.get_env(:aecore, :spend_tx)[:version]
end
