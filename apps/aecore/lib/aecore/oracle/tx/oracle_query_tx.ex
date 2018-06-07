defmodule Aecore.Oracle.Tx.OracleQueryTx do
  @moduledoc """
  Contains the transaction structure for oracle queries
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Oracle.{Oracle, OracleStateTree}
  alias Aeutil.Bits
  alias Aeutil.Hash
  alias Aecore.Account.AccountStateTree

  @type id :: binary()

  @type payload :: %{
          oracle_address: Wallet.pubkey(),
          query_data: Oracle.json(),
          query_fee: non_neg_integer(),
          query_ttl: Oracle.ttl(),
          response_ttl: Oracle.ttl()
        }

  @type t :: %OracleQueryTx{
          oracle_address: Wallet.pubkey(),
          query_data: Oracle.json(),
          query_fee: non_neg_integer(),
          query_ttl: Oracle.ttl(),
          response_ttl: Oracle.ttl()
        }

  @nonce_size 256

  defstruct [
    :oracle_address,
    :query_data,
    :query_fee,
    :query_ttl,
    :response_ttl
  ]

  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  ### getter -----------------------------------------------------------
  def get_sender_address(oracle_query), do: oracle_query.sender_address
  def get_sender_nonce(oracle_query), do: oracle_query.sender_nonce
  def get_oracle_address(oracle_query), do: oracle_query.oracle_address
  def get_query(oracle_query), do: oracle_query.query
  def get_response(oracle_query), do: oracle_query.response
  def get_expires(oracle_query), do: oracle_query.expires
  def get_response_ttl(oracle_query), do: oracle_query.response_ttl
  def get_fee(oracle_query), do: oracle_query.fee
  ### ------------------------------------------------------------------
  ### setter -----------------------------------------------------------
  def set_sender_address(oracle_query, sender_address),
    do: %{oracle_query | sender_address: sender_address}

  def set_sender_nonce(oracle_query, sender_nonce),
    do: %{oracle_query | sender_nonce: sender_nonce}

  def set_oracle_address(oracle_query, oracle_address),
    do: %{oracle_query | oracle_address: oracle_address}

  def set_query(oracle_query, query), do: %{oracle_query | query: query}
  def set_response(oracle_query, response), do: %{oracle_query | response: response}
  def set_expires(oracle_query, expires), do: %{oracle_query | expires: expires}

  def set_response_ttl(oracle_query, response_ttl),
    do: %{oracle_query | response_ttl: response_ttl}

  def set_fee(oracle_query, fee), do: %{oracle_query | fee: fee}
  ### ------------------------------------------------------------------

  @spec init(payload()) :: OracleQueryTx.t()
  def init(%{
        oracle_address: oracle_address,
        query_data: query_data,
        query_fee: query_fee,
        query_ttl: query_ttl,
        response_ttl: response_ttl
      }) do
    %OracleQueryTx{
      oracle_address:
        <<2, 93, 121, 15, 188, 10, 145, 22, 155, 236, 37, 144, 18, 19, 125, 118, 112, 199, 131,
          61, 100, 201, 59, 94, 66, 168, 97, 31, 209, 0, 13, 218, 113>>,
      query_data: query_data,
      query_fee: query_fee,
      query_ttl: query_ttl,
      response_ttl: response_ttl
    }
  end

  @spec validate(OracleQueryTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(
        %OracleQueryTx{
          query_ttl: query_ttl,
          response_ttl: response_ttl,
          oracle_address: oracle_address
        },
        data_tx
      ) do
    senders = DataTx.senders(data_tx)

    cond do
      !Oracle.ttl_is_valid?(query_ttl) ->
        {:error, "#{__MODULE__}: Invalid query ttl"}

      !Oracle.ttl_is_valid?(response_ttl) ->
        {:error, "#{__MODULE__}: Invalid response ttl"}

      !match?(%{type: :relative}, response_ttl) ->
        {:error, "#{__MODULE__}: Invalid ttl type"}

      !Wallet.key_size_valid?(oracle_address) ->
        {:error, "#{__MODULE__}: oracle_adddress size invalid"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec process_chainstate(
          ChainState.account(),
          Oracle.oracles(),
          non_neg_integer(),
          OracleQueryTx.t(),
          DataTx.t()
        ) :: {ChainState.accounts(), Oracle.oracles()}
  def process_chainstate(
        accounts,
        oracles,
        block_height,
        %OracleQueryTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    nonce = DataTx.nonce(data_tx)

    updated_accounts_state =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, tx.query_fee * -1)
      end)

    interaction_object_id = OracleQueryTx.id(sender, nonce, tx.oracle_address)

    io = %{
      sender_address: sender,
      sender_nonce: nonce,
      oracle_address: tx.oracle_address,
      query: tx.query_data,
      has_response: false,
      response: :undefined,
      expires: Oracle.calculate_absolute_ttl(tx.query_ttl, block_height),
      response_ttl: tx.response_ttl.ttl,
      fee: tx.query_fee
    }

    new_oracle_tree = OracleStateTree.insert_query(oracles, io)

    {:ok, {updated_accounts_state, new_oracle_tree}}
  end

  @spec preprocess_check(
          ChainState.accounts(),
          Oracle.oracles(),
          non_neg_integer(),
          OracleQueryTx.t(),
          DataTx.t()
        ) :: :ok
  def preprocess_check(
        accounts,
        oracles,
        block_height,
        tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee - tx.query_fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        {:error, "#{__MODULE__}: Invalid transaction TTL: #{inspect(tx.ttl)}"}

      !OracleStateTree.lookup_oracle?(oracles, tx.oracle_address) ->
        {:error, "#{__MODULE__}: No oracle registered with the address:
         #{inspect(tx.oracle_address)}"}

      !Oracle.data_valid?(
        OracleStateTree.get_oracle(oracles, tx.oracle_address).query_format,
        tx.query_data
      ) ->
        {:error, "#{__MODULE__}: Invalid query data: #{inspect(tx.query_data)}"}

      tx.query_fee < OracleStateTree.get_oracle(oracles, tx.oracle_address).query_fee ->
        {:error, "#{__MODULE__}: The query fee: #{inspect(tx.query_fee)} is
         lower than the one required by the oracle"}

      !is_minimum_fee_met?(tx, fee, block_height) ->
        {:error, "#{__MODULE__}: Fee: #{inspect(fee)} is too low"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          ChainState.accounts(),
          non_neg_integer(),
          OracleQueryTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: ChainState.account()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec get_oracle_query_fee(binary()) :: non_neg_integer()
  def get_oracle_query_fee(oracle_address) do
    Chain.chain_state().oracles
    |> OracleStateTree.get_oracle(oracle_address)
    |> Oracle.get_query_fee()
  end

  @spec is_minimum_fee_met?(OracleQueryTx.t(), non_neg_integer(), non_neg_integer() | nil) ::
          boolean()
  def is_minimum_fee_met?(tx, fee, block_height) do
    tx_query_fee_is_met =
      tx.query_fee >=
        Chain.chain_state().oracles
        |> OracleStateTree.get_oracle(tx.oracle_address)
        |> Oracle.get_query_fee()

    tx_fee_is_met =
      case tx.query_ttl do
        %{ttl: ttl, type: :relative} ->
          fee >= calculate_minimum_fee(ttl)

        %{ttl: ttl, type: :absolute} ->
          if block_height != nil do
            fee >=
              ttl
              |> Oracle.calculate_relative_ttl(block_height)
              |> calculate_minimum_fee()
          else
            true
          end
      end

    tx_fee_is_met && tx_query_fee_is_met
  end

  @spec id(Wallet.pubkey(), non_neg_integer(), Wallet.pubkey()) :: binary()
  def id(sender, nonce, oracle_address) do
    bin = sender <> <<nonce::@nonce_size>> <> oracle_address
    Hash.hash(bin)
  end

  def base58c_encode(bin) do
    Bits.encode58c("qy", bin)
  end

  def base58c_decode(<<"qy$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "#{__MODULE__}: Wrong data"}
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]

    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_query_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
