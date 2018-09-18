defmodule MultiNodeSyncTest do
  use ExUnit.Case

  alias Aetestframework.Worker, as: TestFramework
  alias Aetestframework.Utils
  alias Aetestframework.Worker.Supervisor, as: FrameworkSup
  alias Aecore.Naming.Tx.{NamePreClaimTx, NameClaimTx, NameUpdateTx, NameTransferTx, NameRevokeTx}
  alias Aecore.Oracle.Tx.{OracleExtendTx, OracleRegistrationTx, OracleResponseTx, OracleQueryTx}
  alias Aecore.Account.Tx.SpendTx

  setup do
    FrameworkSup.start_link()

    port1 = Utils.find_port(1)
    TestFramework.new_node(:node1, port1)

    port2 = Utils.find_port(port1 + 1)
    TestFramework.new_node(:node2, port2)

    port3 = Utils.find_port(port2 + 1)
    TestFramework.new_node(:node3, port3)

    port4 = Utils.find_port(port3 + 1)
    TestFramework.new_node(:node4, port4)

    Utils.sync_nodes(:node1, :node2)
    Utils.sync_nodes(:node2, :node3)
    Utils.sync_nodes(:node3, :node4)

    # Check that all nodes have enough number of peers
    assert TestFramework.verify_with_delay(
             fn ->
               [
                 Utils.all_peers_cmd()
                 |> TestFramework.get(:peers_cmd, :node1)
                 |> length(),
                 Utils.all_peers_cmd()
                 |> TestFramework.get(:peers_cmd, :node3)
                 |> length()
               ] ==
                 [
                   Utils.all_peers_cmd()
                   |> TestFramework.get(:peers_cmd, :node2)
                   |> length(),
                   Utils.all_peers_cmd()
                   |> TestFramework.get(:peers_cmd, :node4)
                   |> length()
                 ]
             end,
             5
           ) == true

    on_exit(fn ->
      :ok
    end)
  end

  @tag :sync_test_spend
  test "spend_tx test" do
    Utils.mine_blocks(1, :node1)

    # Create a Spend transaction and add it to the pool
    TestFramework.post(Utils.simulate_spend_tx_cmd(), :spend_tx_cmd, :node1)

    # Check that Spend transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == SpendTx &&
                 Utils.get_tx_from_pool(:node2) == SpendTx &&
                 Utils.get_tx_from_pool(:node3) == SpendTx &&
                 Utils.get_tx_from_pool(:node4) == SpendTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node1)

    # Check if the top Header hash is equal among the nodes
    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node1),
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node3),
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node4)
                 ]
             end,
             5
           ) == true

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test_oracles
  @tag timeout: 100_000
  test "oracles test" do
    Utils.mine_blocks(1, :node2)

    # Create an Oracle Register transaction and add it to the pool
    TestFramework.post(Utils.oracle_register_cmd(), :oracle_register_cmd, :node2)

    # Check that OracleRegister transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == OracleRegistrationTx &&
                 Utils.get_tx_from_pool(:node2) == OracleRegistrationTx &&
                 Utils.get_tx_from_pool(:node3) == OracleRegistrationTx &&
                 Utils.get_tx_from_pool(:node4) == OracleRegistrationTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node2)

    # Create an Oracle Query transaction and add it to the pool
    query_ttl = "%{ttl: 10, type: :relative}"
    response_ttl = "%{ttl: 20, type: :relative}"
    TestFramework.post(Utils.oracle_query_cmd(query_ttl, response_ttl), :oracle_query_cmd, :node2)

    # Check that OracleQuery transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == OracleQueryTx &&
                 Utils.get_tx_from_pool(:node2) == OracleQueryTx &&
                 Utils.get_tx_from_pool(:node3) == OracleQueryTx &&
                 Utils.get_tx_from_pool(:node4) == OracleQueryTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node2)

    %Aecore.Chain.Block{txs: txs} =
      TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node2)

    # Get the required data for creating the correct OracleQueryTxId
    [%Aecore.Tx.SignedTx{data: data}] = txs

    %Aecore.Tx.DataTx{
      nonce: nonce,
      payload: %Aecore.Oracle.Tx.OracleQueryTx{
        oracle_address: %Aecore.Chain.Identifier{value: oracle_address}
      },
      senders: [
        %Aecore.Chain.Identifier{value: sender}
      ]
    } = data

    # Make a OracleRespond transaction and add it to the pool
    TestFramework.post(
      Utils.oracle_respond_cmd(sender, nonce, oracle_address),
      :oracle_respond_cmd,
      :node2
    )

    # Check that OracleResponse transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == OracleResponseTx &&
                 Utils.get_tx_from_pool(:node2) == OracleResponseTx &&
                 Utils.get_tx_from_pool(:node3) == OracleResponseTx &&
                 Utils.get_tx_from_pool(:node4) == OracleResponseTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node2)

    # Create OracleExtend transaction and add it to the pool
    TestFramework.post(Utils.oracle_extend_cmd(), :oracle_extend_cmd, :node2)

    # Check that OracleExtend transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == OracleExtendTx &&
                 Utils.get_tx_from_pool(:node2) == OracleExtendTx &&
                 Utils.get_tx_from_pool(:node3) == OracleExtendTx &&
                 Utils.get_tx_from_pool(:node4) == OracleExtendTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node2)

    # Check if the top Header hash is equal among the nodes
    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node1),
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node3),
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node4)
                 ]
             end,
             5
           ) == true

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test_naming
  @tag timeout: 100_000
  test "namings test" do
    Utils.mine_blocks(1, :node2)

    # Check that top block is equal among the nodes
    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node1),
                 TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node3),
                   TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node4)
                 ]
             end,
             5
           ) == true

    # Create a Naming PreClaim transaction and add it to the pool
    TestFramework.post(Utils.name_preclaim_cmd(), :name_preclaim_cmd, :node2)

    # Check that NamePreClaim transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == NamePreClaimTx &&
                 Utils.get_tx_from_pool(:node2) == NamePreClaimTx &&
                 Utils.get_tx_from_pool(:node3) == NamePreClaimTx &&
                 Utils.get_tx_from_pool(:node4) == NamePreClaimTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node2)

    # Check that top block is equal among the nodes
    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node1),
                 TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node3),
                   TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node4)
                 ]
             end,
             5
           ) == true

    # Check that NameClaim transaction is added to the pool
    TestFramework.post(Utils.name_claim_cmd(), :name_claim_cmd, :node2)

    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == NameClaimTx &&
                 Utils.get_tx_from_pool(:node2) == NameClaimTx &&
                 Utils.get_tx_from_pool(:node3) == NameClaimTx &&
                 Utils.get_tx_from_pool(:node4) == NameClaimTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node2)

    # Check that top block is equal among the nodes
    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node1),
                 TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node3),
                   TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node4)
                 ]
             end,
             5
           ) == true

    # Create a Naming Update transaction and add it to the pool
    TestFramework.post(Utils.name_update_cmd(), :name_update_cmd, :node2)

    # Check that NameUpdate transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == NameUpdateTx &&
                 Utils.get_tx_from_pool(:node2) == NameUpdateTx &&
                 Utils.get_tx_from_pool(:node3) == NameUpdateTx &&
                 Utils.get_tx_from_pool(:node4) == NameUpdateTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node2)

    # Check that top block is equal among the nodes
    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node1),
                 TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node3),
                   TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node4)
                 ]
             end,
             5
           ) == true

    {node2_pub, node2_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair_cmd, :node2)

    # Create a Name Transfer transaction and add it to the pool
    TestFramework.post(Utils.name_transfer_cmd(node2_pub), :name_transfer, :node2)

    # Check that NameTransfer transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == NameTransferTx &&
                 Utils.get_tx_from_pool(:node2) == NameTransferTx &&
                 Utils.get_tx_from_pool(:node3) == NameTransferTx &&
                 Utils.get_tx_from_pool(:node4) == NameTransferTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node2)

    # Check that top block is equal among the nodes
    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node1),
                 TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node3),
                   TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node4)
                 ]
             end,
             5
           ) == true

    # Create a Naming Revoke transaction and add it to the pool
    TestFramework.post(Utils.name_revoke_cmd(node2_pub, node2_priv), :name_revoke_cmd, :node2)

    # Check that NameRevoke transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == NameRevokeTx &&
                 Utils.get_tx_from_pool(:node2) == NameRevokeTx &&
                 Utils.get_tx_from_pool(:node3) == NameRevokeTx &&
                 Utils.get_tx_from_pool(:node4) == NameRevokeTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node2)

    # Check if the top Header hash is equal among the nodes
    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node1),
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node3),
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node4)
                 ]
             end,
             5
           ) == true

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test_accounts
  test "balance test" do
    # Get signing keys of all nodes
    {node1_pub, node1_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair_cmd, :node1)
    {node2_pub, node2_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair_cmd, :node2)
    {node3_pub, node3_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair_cmd, :node3)
    {node4_pub, _} = TestFramework.get(Utils.sign_keys_cmd(), :keypair_cmd, :node4)

    # Mine 2 blocks, so that node1 has enough tokens to spend
    Utils.mine_blocks(2, :node1)

    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node1),
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node3),
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node4)
                 ]
             end,
             5
           ) == true

    assert TestFramework.verify_with_delay(
             fn ->
               TestFramework.get(Utils.balance_cmd(node1_pub), :balance_cmd, :node1) ==
                 20_000_000_000_000_000_000
             end,
             5
           ) == true

    amount1 = 50
    fee = 10
    payload = <<"test">>

    # Create SpendTx transaction
    # Send 50 tokens from node1 to node3
    # Add the transaction to the pool
    TestFramework.post(
      Utils.send_tokens_cmd(
        node1_pub,
        node1_priv,
        node3_pub,
        amount1,
        fee,
        payload
      ),
      :send_tokens_cmd,
      :node1
    )

    # Check that Spend transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == SpendTx &&
                 Utils.get_tx_from_pool(:node2) == SpendTx &&
                 Utils.get_tx_from_pool(:node3) == SpendTx &&
                 Utils.get_tx_from_pool(:node4) == SpendTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node1)

    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node1),
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node3),
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node4)
                 ]
             end,
             5
           ) == true

    assert TestFramework.verify_with_delay(
             fn ->
               TestFramework.get(Utils.balance_cmd(node3_pub), :balance_cmd, :node3) == 50
             end,
             10
           ) == true

    # Create SpendTx transaction
    # Send 20 tokens from node3 to node2
    # Add the transaction to the pool
    amount2 = 20

    TestFramework.post(
      Utils.send_tokens_cmd(
        node3_pub,
        node3_priv,
        node2_pub,
        amount2,
        fee,
        payload
      ),
      :send_tokens_cmd,
      :node3
    )

    # Check that Spend transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == SpendTx &&
                 Utils.get_tx_from_pool(:node2) == SpendTx &&
                 Utils.get_tx_from_pool(:node3) == SpendTx &&
                 Utils.get_tx_from_pool(:node4) == SpendTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node3)

    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node1),
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node3),
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node4)
                 ]
             end,
             5
           ) == true

    assert TestFramework.verify_with_delay(
             fn ->
               TestFramework.get(Utils.balance_cmd(node2_pub), :balance_cmd, :node2) == 20
             end,
             5
           ) == true

    # Create SpendTx transaction
    # Send 10 tokens from node2 to node4
    # Add the transaction to the pool
    amount3 = 10

    TestFramework.post(
      Utils.send_tokens_cmd(
        node2_pub,
        node2_priv,
        node4_pub,
        amount3,
        fee,
        payload
      ),
      :send_tokens_cmd,
      :node2
    )

    # Check that Spend transaction is added to the pool
    assert TestFramework.verify_with_delay(
             fn ->
               Utils.get_tx_from_pool(:node1) == SpendTx &&
                 Utils.get_tx_from_pool(:node2) == SpendTx &&
                 Utils.get_tx_from_pool(:node3) == SpendTx &&
                 Utils.get_tx_from_pool(:node4) == SpendTx
             end,
             5
           ) == true

    Utils.mine_blocks(1, :node2)

    assert TestFramework.verify_with_delay(
             fn ->
               [
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node1),
                 TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node2)
               ] ==
                 [
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node3),
                   TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node4)
                 ]
             end,
             5
           ) == true

    # Check that all nodes have correct amount
    assert TestFramework.verify_with_delay(
             fn ->
               TestFramework.get(Utils.balance_cmd(node1_pub), :balance_cmd, :node4) ==
                 29_999_999_999_999_999_950 &&
                 TestFramework.get(Utils.balance_cmd(node2_pub), :balance_cmd, :node4) ==
                   10_000_000_000_000_000_010 &&
                 TestFramework.get(Utils.balance_cmd(node3_pub), :balance_cmd, :node4) ==
                   10_000_000_000_000_000_030 &&
                 TestFramework.get(Utils.balance_cmd(node4_pub), :balance_cmd, :node4) == 10
             end,
             5
           ) == true

    TestFramework.delete_all_nodes()
  end
end
