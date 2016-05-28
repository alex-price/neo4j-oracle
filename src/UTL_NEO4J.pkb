create or replace package body utl_neo4j as

  /*
   * Endpoint Definition
   */

  -- Endpoint constructor
  function endpoint_new(
    p_url      varchar2,
    p_username varchar2,
    p_password varchar2
  ) return endpoint_rectype is
    l_endpoint endpoint_rectype;
  begin
    l_endpoint.url := p_url;
    l_endpoint.username := p_username;
    l_endpoint.password := p_password;
    return l_endpoint;
  end;

  -- Endpoint constructor
  function endpoint_copy(
    p_endpoint endpoint_rectype,
    p_url      varchar2 default null,
    p_username varchar2 default null,
    p_password varchar2 default null
  ) return endpoint_rectype is
  begin
    return endpoint_new(nvl(p_url, p_endpoint.url),
                        nvl(p_username, p_endpoint.username),
                        nvl(p_password, p_endpoint.password));
  end;

  /*
   * Util
   */

  -- Wrap cypher in JSON object
  function to_json_request(
    p_cypher varchar2
  ) return varchar2 is
  begin
    return '{"statements":[{"statement":"' || p_cypher || '"}]}';
  end;

  /*
   * Request Handling
   */

  -- Create new request
  function request_create(
    p_endpoint endpoint_rectype
  ) return utl_http.req is
    l_req utl_http.req;
  begin
    l_req := utl_http.begin_request(p_endpoint.url, 'POST');
    utl_http.set_authentication(l_req, p_endpoint.username, p_endpoint.password);
    utl_http.set_header(l_req, 'Accept', 'application/json; charset=UTF-8');
    utl_http.set_header(l_req, 'Content-Type', 'application/json');
    utl_http.set_persistent_conn_support(l_req, true);
    utl_http.set_response_error_check(l_req, true);
    utl_http.set_transfer_timeout(l_req, 300);
    return l_req;
  end;

  -- Execute request, handle errors, return response
  function request_send(
    p_req in out utl_http.req
  ) return utl_http.resp is
    l_resp          utl_http.resp;
    l_resp_json     varchar2(32767);
    l_regexp        varchar(100) := '^.*"errors":\[{"code":"(.*?)","message":"(.*)"}]}$';
    l_error_code    varchar2(4000);
    l_error_message varchar2(32767);
  begin
    l_resp := utl_http.get_response(p_req);

    -- All requests against the transactional endpoint will return 200 or 201
    -- status code, regardless of whether statements were successfully executed
    if (l_resp.status_code not in (utl_http.HTTP_OK, utl_http.HTTP_CREATED)) then
      raise_application_error(-20101, 'Error communicating with Neo4j!');
    end if;

    -- Read response
    utl_http.read_line(l_resp, l_resp_json);

    -- If the response includes an error:
    if (substr(l_resp_json, -3) <> '[]}') then
      -- Extract error detail and log:
      if (regexp_instr(l_resp_json, l_regexp) <> 0) then
        l_error_code := regexp_replace(l_resp_json, l_regexp, '\1');
        l_error_message := regexp_replace(l_resp_json, l_regexp, '\2');

        -- TODO: Define table and uncomment lines
        --insert into neo4j_errors(code, message, created_dtm)
        --values (l_error_code, l_error_message, sysdate);

        raise_application_error(-20102, 'Error within Neo4j!');
      else
        raise_application_error(-20103, 'Error! Unable to extract Neo4j error detail.');
      end if;
    end if;

    return l_resp;
  exception
    when others then
      utl_http.end_response(l_resp);
      raise;
  end;

  /*
   * Transaction Handling
   */

  -- Open new transaction
  function transaction_create(
    p_endpoint endpoint_rectype
  ) return endpoint_rectype is
    l_req  utl_http.req;
    l_resp utl_http.resp;
    l_url  varchar2(4000);
  begin
    l_req := request_create(p_endpoint);
    l_resp := request_send(l_req);
    utl_http.get_header_by_name(l_resp, 'Location', l_url);
    utl_http.end_response(l_resp);
    return endpoint_copy(p_endpoint, l_url);
  exception
    when others then
      utl_http.end_response(l_resp);
      raise;
  end;

  -- Commit open transaction
  procedure transaction_commit(
    p_endpoint endpoint_rectype
  ) as
    l_req  utl_http.req;
    l_resp utl_http.resp;
    l_commit_endpoint endpoint_rectype;
  begin
    l_commit_endpoint := endpoint_new(concat(p_endpoint.url, '/commit'),
                                      p_endpoint.username,
                                      p_endpoint.password);
    l_req := request_create(l_commit_endpoint);
    l_resp := request_send(l_req);
    utl_http.end_response(l_resp);
  exception
    when others then
      utl_http.end_response(l_resp);
      dbms_output.put_line(SQLERRM);
      dbms_output.put_line(dbms_utility.format_error_backtrace);
  end;

  -- Commit open transaction if necessary, return new transaction
  procedure transaction_commit_periodic(
    p_endpoint         in     endpoint_rectype,
    p_transaction      in out endpoint_rectype,
    p_query_count      in out number,
    p_commit_interval  in     number
  ) as
    l_new_transaction endpoint_rectype;
  begin
      if (p_commit_interval > 0
          and p_query_count >= p_commit_interval) then
        transaction_commit(p_transaction);
        l_new_transaction := transaction_create(p_endpoint);
        p_transaction := l_new_transaction;
        p_query_count := 1;
      else
        p_query_count := p_query_count + 1;
      end if;
  end;

  -- Rollback transaction (discard errors)
  procedure transaction_rollback(
    p_endpoint endpoint_rectype
  ) as
    l_req  utl_http.req;
    l_resp utl_http.resp;
  begin
    l_req := utl_http.begin_request(p_endpoint.url, 'DELETE');
    l_resp := request_send(l_req);
    utl_http.end_response(l_resp);
  exception
    when others then
      utl_http.end_response(l_resp);
      dbms_output.put_line(SQLERRM);
      dbms_output.put_line(dbms_utility.format_error_backtrace);
  end;

  -- Execute cypher against an open transaction
  procedure transaction_run(
    p_transaction endpoint_rectype,
    p_statement   varchar2
  ) as
    l_req utl_http.req;
    l_req_body varchar2(32767);
    l_resp utl_http.resp;
  begin
    -- Prepare request
    l_req := request_create(p_transaction);
    l_req_body := to_json_request(p_statement);
    utl_http.set_header(l_req, 'Content-Length', lengthb(l_req_body));
    utl_http.write_text(l_req, l_req_body);

    -- Send request
    l_resp := request_send(l_req);
    utl_http.end_response(l_resp);
  exception
    when others then
      utl_http.end_response(l_resp);
      raise;
  end;

end;
