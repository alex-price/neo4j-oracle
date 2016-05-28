create or replace package utl_neo4j as

  /*
   * Endpoint Definition
   */

  type endpoint_rectype is record (
    url      varchar2(4000),
    username varchar2(100),
    password varchar2(100)
  );

  function endpoint_new(
    p_url      varchar2,
    p_username varchar2,
    p_password varchar2
  ) return endpoint_rectype;

  function endpoint_copy(
    p_endpoint endpoint_rectype,
    p_url      varchar2 default null,
    p_username varchar2 default null,
    p_password varchar2 default null
  ) return endpoint_rectype;

  /*
   * Util
   */

  -- Wrap cypher in JSON object
  function to_json_request(
    p_cypher varchar2
  ) return varchar2;

  /*
   * Request Handling
   */

  -- Create new request
  function request_create(
    p_endpoint endpoint_rectype
  ) return utl_http.req;

  -- Execute request, handle errors, return response
  function request_send(
    p_req in out utl_http.req
  ) return utl_http.resp;

  /*
   * Transaction Handling
   */

  -- Open new transaction
  function transaction_create(
    p_endpoint endpoint_rectype
  ) return endpoint_rectype;

  -- Commit open transaction
  procedure transaction_commit(
    p_endpoint endpoint_rectype
  );

  -- Commit open transaction if necessary, return new transaction
  procedure transaction_commit_periodic(
    p_endpoint         in     endpoint_rectype,
    p_transaction      in out endpoint_rectype,
    p_query_count      in out number,
    p_commit_interval  in     number
  );

  -- Rollback transaction (discard errors)
  procedure transaction_rollback(
    p_endpoint endpoint_rectype
  );

  -- Execute cypher against open transaction
  procedure transaction_run(
    p_transaction endpoint_rectype,
    p_statement   varchar2
  );

end;
