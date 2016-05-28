create or replace package body com_neo4j as

  -- Example implementation; Modify to suit your needs
  procedure export_to_neo4j(
    p_url             varchar2,
    p_username        varchar2,
    p_password        varchar2,
    p_commit_interval number default 0
  ) as
    l_req         utl_http.req;
    l_resp        utl_http.resp;
    l_endpoint    utl_neo4j.endpoint_rectype;
    l_transaction utl_neo4j.endpoint_rectype;
    l_cypher      varchar(32767);
    l_query_count number(10) := 1;
  begin
    -- Enable detailed UTL_HTTP exceptions
    utl_http.set_detailed_excp_support(true);

    -- Define the endpoint
    l_endpoint := utl_neo4j.endpoint_copy(DEFAULT_ENDPOINT, p_url, p_username, p_password);

    -- Open new transaction
    l_transaction := utl_neo4j.transaction_create(l_endpoint);

    for node_crec in (select sys_guid() guid
                      from dual
                      connect by level <= 100)
    loop
      -- Declare statement
      l_cypher := 'merge (n:Node {guid: ''' || node_crec.guid || '''}) '
               || 'on create set n.created_dtm = ''' || sysdate || ''' '
               || 'on match set n.modified_dtm = ''' || sysdate || ''';';

      -- Execute statement
      utl_neo4j.transaction_run(l_transaction, l_cypher);

      -- Periodically commit and open new transaction, as necessary
      utl_neo4j.transaction_commit_periodic(l_endpoint,
                                            l_transaction,
                                            l_query_count,
                                            p_commit_interval);
    end loop;

    utl_neo4j.transaction_commit(l_transaction);
    dbms_output.put_line('Export successful.');
  exception
    when others then
      dbms_output.put_line('Export failed; See log table for details.');
      utl_neo4j.transaction_rollback(l_transaction);
  end;

end;
