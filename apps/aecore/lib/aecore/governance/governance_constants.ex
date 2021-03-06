defmodule Aecore.Governance.GovernanceConstants do
  @moduledoc """
  Module containing governance constants
  """

  @number_of_blocks_for_target_recalculation 10

  # 60sec * 1000ms * 5 = 300_000ms
  @expected_mine_rate_ms 300_000

  @coinbase_transaction_amount 10_000_000_000_000_000_000

  @minimum_fee 1

  @oracle_register_base_fee 4
  @oracle_query_base_fee 2
  @oracle_response_base_fee 2
  @oracle_extend_base_fee 1

  @oracle_ttl_fee_per_block 0.001

  # 30min
  @time_validation_future_limit_ms 1_800_000

  @split_name_symbol "."

  @name_registrars [@split_name_symbol <> "test"]

  @pre_claim_ttl 300

  @revoke_expiration_ttl 2016

  @client_ttl_limit 86_400

  @claim_expire_by_relative_limit 50_000

  @name_split_check 2

  @name_claim_burned_fee 3

  @max_txs_per_block 10_946

  # getter functions with same name for use in other modules

  @spec number_of_blocks_for_target_recalculation :: non_neg_integer()
  def number_of_blocks_for_target_recalculation, do: @number_of_blocks_for_target_recalculation

  @spec expected_mine_rate_ms :: non_neg_integer()
  def expected_mine_rate_ms, do: @expected_mine_rate_ms

  @spec coinbase_transaction_amount :: non_neg_integer()
  def coinbase_transaction_amount, do: @coinbase_transaction_amount

  @spec minimum_fee :: non_neg_integer()
  def minimum_fee, do: @minimum_fee

  @spec oracle_register_base_fee :: non_neg_integer()
  def oracle_register_base_fee, do: @oracle_register_base_fee

  @spec oracle_query_base_fee :: non_neg_integer()
  def oracle_query_base_fee, do: @oracle_query_base_fee

  @spec oracle_response_base_fee :: non_neg_integer()
  def oracle_response_base_fee, do: @oracle_response_base_fee

  @spec oracle_extend_base_fee :: non_neg_integer()
  def oracle_extend_base_fee, do: @oracle_extend_base_fee

  @spec oracle_ttl_fee_per_block :: float()
  def oracle_ttl_fee_per_block, do: @oracle_ttl_fee_per_block

  @spec time_validation_future_limit_ms :: non_neg_integer()
  def time_validation_future_limit_ms, do: @time_validation_future_limit_ms

  @spec split_name_symbol :: String.t()
  def split_name_symbol, do: @split_name_symbol

  @spec name_registrars :: list(String.t())
  def name_registrars, do: @name_registrars

  @spec pre_claim_ttl :: non_neg_integer()
  def pre_claim_ttl, do: @pre_claim_ttl

  @spec revoke_expiration_ttl :: non_neg_integer()
  def revoke_expiration_ttl, do: @revoke_expiration_ttl

  @spec client_ttl_limit :: non_neg_integer()
  def client_ttl_limit, do: @client_ttl_limit

  @spec claim_expire_by_relative_limit :: non_neg_integer()
  def claim_expire_by_relative_limit, do: @claim_expire_by_relative_limit

  @spec name_split_check :: non_neg_integer()
  def name_split_check, do: @name_split_check

  @spec name_claim_burned_fee :: non_neg_integer()
  def name_claim_burned_fee, do: @name_claim_burned_fee

  @spec max_txs_per_block :: non_neg_integer()
  def max_txs_per_block, do: @max_txs_per_block
end
