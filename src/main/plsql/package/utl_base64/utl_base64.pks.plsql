create or replace package utl_base64 is
  function decode_base64(p_clob_in in clob) return blob;

  function encode_base64(p_blob_in in blob) return clob;
end;
/