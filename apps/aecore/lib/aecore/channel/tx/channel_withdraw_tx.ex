defmodule Aecore.Channel.Tx.ChannelWithdrawTx do
  @moduledoc """
  Aecore structure of ChannelWithdrawTx transaction data.
  """

  use Aecore.Tx.Transaction
  @behaviour Aecore.Channel.ChannelTransaction

  alias Aecore.Channel.Tx.ChannelWithdrawTx
  alias Aecore.Tx.{SignedTx, DataTx}
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Chain.Chainstate
  alias Aecore.Channel.{ChannelStateOnChain, ChannelStateTree, ChannelOffChainUpdate}
  alias Aecore.Chain.Identifier
  alias Aecore.Channel.Updates.ChannelWithdrawUpdate

  require Logger

  @version 1

  @typedoc "Expected structure for the ChannelWithdrawTx Transaction"
  @type payload :: %{
          channel_id: binary(),
          amount: non_neg_integer(),
          state_hash: binary(),
          sequence: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate."
  @type tx_type_state() :: ChannelStateTree.t()

  @typedoc "Structure of the ChannelWithdraw Transaction type"
  @type t :: %ChannelWithdrawTx{
          channel_id: binary(),
          amount: non_neg_integer(),
          state_hash: binary(),
          sequence: non_neg_integer()
        }

  @doc """
  Definition of the ChannelWithdrawTx structure

  # Parameters
  - channel_id: id of the channel for which the transaction is meant
  - amount: the amount of tokens withdrawn from the channel
  - state_hash: root hash of the offchain chainstate after applying this transaction to it
  - sequence: sequence of the channel after applying this transaction to the channel
  """
  defstruct [
    :channel_id,
    :amount,
    :state_hash,
    :sequence
  ]

  @spec get_chain_state_name :: atom()
  def get_chain_state_name, do: :channels

  @spec sender_type() :: Identifier.type()
  def sender_type, do: :account

  @spec init(payload()) :: ChannelWithdrawTx.t()
  def init(%{
        channel_id: channel_id,
        amount: amount,
        state_hash: state_hash,
        sequence: sequence
      }) do
    %ChannelWithdrawTx{
      channel_id: channel_id,
      amount: amount,
      state_hash: state_hash,
      sequence: sequence
    }
  end

  @doc """
  Validates the transaction without considering state
  """
  @spec validate(ChannelWithdrawTx.t(), DataTx.t()) :: :ok | {:error, reason()}
  def validate(
        %ChannelWithdrawTx{
          channel_id: channel_id,
          amount: amount,
          state_hash: state_hash,
          sequence: sequence
        },
        %DataTx{senders: senders}
      ) do
    cond do
      byte_size(channel_id) != 32 ->
        {:error, "#{__MODULE__}: Invalid channel id"}

      amount <= 0 ->
        {:error, "#{__MODULE__}: Can't withdraw zero or negative amount of tokens"}

      byte_size(state_hash) != 32 ->
        {:error, "#{__MODULE__}: Invalid state hash"}

      sequence < 0 ->
        {:error, "#{__MODULE__}: Invalid sequence"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Multi party withdrawal is (currently) disallowed"}

      true ->
        :ok
    end
  end

  @doc """
  Withdraws tokens from the channel
  """
  @spec process_chainstate(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelWithdrawTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), ChannelStateTree.t()}} | no_return()
  def process_chainstate(
        accounts,
        channels,
        block_height,
        %ChannelWithdrawTx{
          channel_id: channel_id,
          amount: amount,
          state_hash: state_hash,
          sequence: sequence
        },
        %DataTx{
          nonce: nonce,
          senders: [
            %Identifier{value: main_sender, type: :account}
          ]
        }
      ) do
    new_accounts =
      AccountStateTree.update(accounts, main_sender, fn account ->
        Account.apply_transfer!(account, block_height, amount)
        |> Account.apply_nonce!(nonce)
      end)

    new_channels =
      ChannelStateTree.update!(channels, channel_id, fn channel ->
        ChannelStateOnChain.apply_withdraw(channel, main_sender, amount, sequence, state_hash)
      end)

    {:ok, {new_accounts, new_channels}}
  end

  @doc """
  Validates the transaction with state considered
  """
  @spec preprocess_check(
          Chainstate.accounts(),
          ChannelStateTree.t(),
          non_neg_integer(),
          ChannelWithdrawTx.t(),
          DataTx.t()
        ) :: :ok | {:error, reason()}
  def preprocess_check(
        accounts,
        channels,
        _block_height,
        %ChannelWithdrawTx{
          channel_id: channel_id,
          amount: amount,
          sequence: sequence
        },
        %DataTx{
          fee: fee,
          senders: [
            %Identifier{value: main_sender, type: :account}
          ]
        }
      ) do
    channel = ChannelStateTree.get(channels, channel_id)

    cond do
      AccountStateTree.get(accounts, main_sender).balance - fee + amount < 0 ->
        {:error, "#{__MODULE__}: Negative balance of the withdrawing account"}

      channel == :none ->
        {:error, "#{__MODULE__}: Channel does not exists"}

      !ChannelStateOnChain.active?(channel) ->
        {:error, "#{__MODULE__}: Can't withdraw from inactive channel."}

      true ->
        ChannelStateOnChain.validate_withdraw(channel, main_sender, amount, sequence)
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          ChannelWithdrawTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, %DataTx{} = data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(DataTx.t(), tx_type_state(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(%DataTx{fee: fee}, _chain_state, _block_height) do
    fee >= GovernanceConstants.minimum_fee()
  end

  @spec encode_to_list(ChannelWithdrawTx.t(), DataTx.t()) :: list()
  def encode_to_list(
        %ChannelWithdrawTx{} = tx,
        %DataTx{senders: [to]} = data_tx
      ) do
    [
      :binary.encode_unsigned(@version),
      Identifier.create_encoded_to_binary(tx.channel_id, :channel),
      Identifier.encode_to_binary(to),
      :binary.encode_unsigned(tx.amount),
      :binary.encode_unsigned(data_tx.ttl),
      :binary.encode_unsigned(data_tx.fee),
      tx.state_hash,
      :binary.encode_unsigned(tx.sequence),
      :binary.encode_unsigned(data_tx.nonce)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, DataTx.t()} | {:error, reason()}
  def decode_from_list(@version, [
        encoded_channel_id,
        encoded_to,
        amount,
        ttl,
        fee,
        state_hash,
        sequence,
        nonce
      ])
      when is_binary(state_hash) do
    with {:ok, _} <- Identifier.decode_from_binary_to_value(encoded_to, :account),
         {:ok, channel_id} <- Identifier.decode_from_binary_to_value(encoded_channel_id, :channel) do
      payload = %ChannelWithdrawTx{
        channel_id: channel_id,
        amount: :binary.decode_unsigned(amount),
        state_hash: state_hash,
        sequence: sequence
      }

      DataTx.init_binary(
        ChannelWithdrawTx,
        payload,
        [encoded_to],
        :binary.decode_unsigned(fee),
        :binary.decode_unsigned(nonce),
        :binary.decode_unsigned(ttl)
      )
    else
      {:error, _} = error ->
        error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end

  @doc """
    Get a list of offchain updates to the offchain chainstate
  """
  @spec offchain_updates(SignedTx.t() | DataTx.t()) :: list(ChannelOffChainUpdate.update_types())
  def offchain_updates(%SignedTx{data: data}) do
    offchain_updates(data)
  end

  def offchain_updates(%DataTx{
        type: ChannelWithdrawTx,
        payload: tx,
        senders: [%Identifier{value: to}]
      }) do
    [ChannelWithdrawUpdate.new(tx, to)]
  end
end