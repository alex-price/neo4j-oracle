create or replace package com_neo4j as

  DEFAULT_URL constant varchar2(4000) := 'http://localhost:7474/db/data/transaction';
  DEFAULT_USERNAME constant varchar2(100) := 'neo4j';
  DEFAULT_PASSWORD constant varchar2(100) := 'neo4j';

  DEFAULT_ENDPOINT constant utl_neo4j.endpoint_rectype :=
    utl_neo4j.endpoint_new(DEFAULT_URL, DEFAULT_USERNAME, DEFAULT_PASSWORD);

  -- Sample implementation, modify to suit your needs
  procedure export_to_neo4j(
    p_url             varchar2,
    p_username        varchar2,
    p_password        varchar2,
    p_commit_interval number default 0
  );

end;
