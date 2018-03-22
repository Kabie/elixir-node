defmodule Aecore.Structures.OracleExtendTxData do
  @behaviour Aecore.Structures.Transaction

  alias __MODULE__
  alias Aecore.Oracle.Oracle
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet

  require Logger

  @type payload :: %{
          ttl: non_neg_integer()
        }

  @type t :: %OracleExtendTxData{
          ttl: non_neg_integer()
        }

  defstruct [:ttl]
  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name(), do: :oracles

  @spec init(payload()) :: OracleExtendTxData.t()
  def init(%{ttl: ttl}) do
    %OracleExtendTxData{ttl: ttl}
  end

  @spec is_valid?(OracleExtendTxData.t()) :: boolean()
  def is_valid?(%OracleExtendTxData{ttl: ttl}) do
    ttl > 0
  end

  @spec process_chainstate!(
          OracleExtendTxData.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          ChainState.account(),
          Oracle.registered_oracles()
        ) :: {ChainState.accounts(), Oracle.registered_oracles()}
  def process_chainstate!(
        %OracleExtendTxData{} = tx,
        from_acc,
        fee,
        nonce,
        block_height,
        accounts,
        %{registered_oracles: registered_oracles}
      ) do
    case preprocess_check(
           tx,
           from_acc,
           Map.get(accounts, from_acc, Account.empty()),
           fee,
           nonce,
           block_height,
           registered_oracles
         ) do
      :ok ->
        new_from_account_state =
          Map.get(accounts, from_acc, Account.empty())
          |> deduct_fee(fee)

        updated_accounts_chainstate = Map.put(accounts, from_acc, new_from_account_state)

        oracle_ttl = get_in(registered_oracles, [from_acc, :tx, Access.key(:ttl)])

        updated_registered_oracles =
          put_in(registered_oracles, [from_acc, :tx, Access.key(:ttl)], %{
            oracle_ttl
            | ttl: oracle_ttl.ttl + tx.ttl
          })

        {updated_accounts_chainstate, updated_registered_oracles}

      {:error, _reason} = err ->
        throw(err)
    end
  end

  @spec preprocess_check(
          OracleExtendTxData.t(),
          Wallet.pubkey(),
          ChainState.account(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Oracle.registered_oracles()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, from_acc, account_state, fee, nonce, _block_height, registered_oracles) do
    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      account_state.nonce >= nonce ->
        {:error, "Nonce too small"}

      !Map.has_key?(registered_oracles, from_acc) ->
        {:error, "Account isn't a registered operator"}

      fee < calculate_minimum_fee(tx.ttl) ->
        {:error, "Fee is too low"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), non_neg_integer()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  @spec calculate_minimum_fee(integer()) :: integer()
  def calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_extend_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end