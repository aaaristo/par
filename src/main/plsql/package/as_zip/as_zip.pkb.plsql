create or replace package body as_zip
is

--
  function blob2num( p_blob blob, p_len integer, p_pos integer )
  return number
  is
  begin
    return utl_raw.cast_to_binary_integer( dbms_lob.substr( p_blob, p_len, p_pos ), utl_raw.little_endian );
  end;
--
  function raw2varchar2( p_raw raw, p_encoding varchar2 )
  return varchar2
  is
  begin
    return nvl( utl_i18n.raw_to_char( p_raw, p_encoding )
              , utl_i18n.raw_to_char( p_raw, utl_i18n.map_charset( p_encoding, utl_i18n.GENERIC_CONTEXT, utl_i18n.IANA_TO_ORACLE ) )
              );
  end;
--
  function file2blob
    ( p_dir varchar2
    , p_file_name varchar2
    )
  return blob
  is
    file_lob bfile;
    file_blob blob;
  begin
    file_lob := bfilename( p_dir, p_file_name );
    dbms_lob.open( file_lob, dbms_lob.file_readonly );
    dbms_lob.createtemporary( file_blob, true );
    dbms_lob.loadfromfile( file_blob, file_lob, dbms_lob.lobmaxsize );
    dbms_lob.close( file_lob );
    return file_blob;
  exception
    when others then
      if dbms_lob.isopen( file_lob ) = 1
      then
        dbms_lob.close( file_lob );
      end if;
      if dbms_lob.istemporary( file_blob ) = 1
      then
        dbms_lob.freetemporary( file_blob );
      end if;
      raise;
  end;
--
  function get_file_list
    ( p_dir varchar2
    , p_zip_file varchar2
    , p_encoding varchar2 := null
    )
  return file_list
  is
  begin
    return get_file_list( file2blob( p_dir, p_zip_file ), p_encoding );
  end;
--
  function get_file_list
    ( p_zipped_blob blob
    , p_encoding varchar2 := null
    )
  return file_list
  is
    t_ind integer;
    t_hd_ind integer;
    t_rv file_list;
  begin
    t_ind := dbms_lob.getlength( p_zipped_blob ) - 21;
    loop
      exit when dbms_lob.substr( p_zipped_blob, 4, t_ind ) = hextoraw( '504B0506' ) or t_ind < 1;
      t_ind := t_ind - 1;
    end loop;
--
    if t_ind <= 0
    then
      return null;
    end if;
--
    t_hd_ind := blob2num( p_zipped_blob, 4, t_ind + 16 ) + 1;
    t_rv := file_list();
    t_rv.extend( blob2num( p_zipped_blob, 2, t_ind + 10 ) );
    for i in 1 .. blob2num( p_zipped_blob, 2, t_ind + 8 )
    loop
      t_rv( i ) := raw2varchar2
                     ( dbms_lob.substr( p_zipped_blob
                                      , blob2num( p_zipped_blob, 2, t_hd_ind + 28 )
                                      , t_hd_ind + 46
                                      )
                     , p_encoding
                     );
      t_hd_ind := t_hd_ind + 46
                + blob2num( p_zipped_blob, 2, t_hd_ind + 28 )
                + blob2num( p_zipped_blob, 2, t_hd_ind + 30 )
                + blob2num( p_zipped_blob, 2, t_hd_ind + 32 );
    end loop;
--
    return t_rv;
  end;
--
  function get_file
    ( p_dir varchar2
    , p_zip_file varchar2
    , p_file_name varchar2
    , p_encoding varchar2 := null
    )
  return blob
  is
  begin
    return get_file( file2blob( p_dir, p_zip_file ), p_file_name, p_encoding );
  end;
--
  function get_file
    ( p_zipped_blob blob
    , p_file_name varchar2
    , p_encoding varchar2 := null
    )
  return blob
  is
    t_tmp blob;
    t_ind integer;
    t_hd_ind integer;
    t_fl_ind integer;
  begin
    t_ind := dbms_lob.getlength( p_zipped_blob ) - 21;
    loop
      exit when dbms_lob.substr( p_zipped_blob, 4, t_ind ) = hextoraw( '504B0506' ) or t_ind < 1;
      t_ind := t_ind - 1;
    end loop;
--
    if t_ind <= 0
    then
      return null;
    end if;
--
    t_hd_ind := blob2num( p_zipped_blob, 4, t_ind + 16 ) + 1;
    for i in 1 .. blob2num( p_zipped_blob, 2, t_ind + 8 )
    loop
      if p_file_name = raw2varchar2
                         ( dbms_lob.substr( p_zipped_blob
                                          , blob2num( p_zipped_blob, 2, t_hd_ind + 28 )
                                          , t_hd_ind + 46
                                          )
                         , p_encoding
                         )
      then
        if blob2num( p_zipped_blob, 4, t_hd_ind + 24 ) = 0 -- uncompressed length
        then
          if substr( p_file_name, -1 ) = '/'
          then  -- directory/folder
            return null;
          else -- empty file
            return empty_blob();
          end if;
        end if;
--
        if dbms_lob.substr( p_zipped_blob, 2, t_hd_ind + 10 ) = hextoraw( '0800' ) -- deflate
        then
          t_fl_ind := blob2num( p_zipped_blob, 4, t_hd_ind + 42 );
          t_tmp := hextoraw( '1F8B0800000000000003' ); -- gzip header
          dbms_lob.copy( t_tmp
                       , p_zipped_blob
                       , blob2num( p_zipped_blob, 4, t_fl_ind + 19 )
                       , 11
                       , t_fl_ind + 31
                       + blob2num( p_zipped_blob, 2, t_fl_ind + 27 )
                       + blob2num( p_zipped_blob, 2, t_fl_ind + 29 )
                       );
          dbms_lob.append( t_tmp, dbms_lob.substr( p_zipped_blob, 4, t_fl_ind + 15 ) );
          dbms_lob.append( t_tmp, dbms_lob.substr( p_zipped_blob, 4, t_fl_ind + 23 ) );
          return utl_compress.lz_uncompress( t_tmp );
        end if;
--
        if dbms_lob.substr( p_zipped_blob, 2, t_hd_ind + 10 ) = hextoraw( '0000' ) -- The file is stored (no compression)
        then
          t_fl_ind := blob2num( p_zipped_blob, 4, t_hd_ind + 42 );
          return dbms_lob.substr( p_zipped_blob
                                , blob2num( p_zipped_blob, 4, t_fl_ind + 19 )
                                , t_fl_ind + 31
                                + blob2num( p_zipped_blob, 2, t_fl_ind + 27 )
                                + blob2num( p_zipped_blob, 2, t_fl_ind + 29 )
                                );
        end if;
      end if;
      t_hd_ind := t_hd_ind + 46
                + blob2num( p_zipped_blob, 2, t_hd_ind + 28 )
                + blob2num( p_zipped_blob, 2, t_hd_ind + 30 )
                + blob2num( p_zipped_blob, 2, t_hd_ind + 32 );
    end loop;
--
    return null;
  end;
--
  function little_endian( p_big number, p_bytes pls_integer := 4 )
  return raw
  is
  begin
    return utl_raw.substr( utl_raw.cast_from_binary_integer( p_big, utl_raw.little_endian ), 1, p_bytes );
  end;
--
  procedure add1file
    ( p_zipped_blob in out blob
    , p_name varchar2
    , p_content blob
    )
  is
    t_now date;
    t_blob blob;
    t_clen integer;
  begin
    t_now := sysdate;
    t_blob := utl_compress.lz_compress( p_content );
    t_clen := dbms_lob.getlength( t_blob );
    if p_zipped_blob is null
    then
      dbms_lob.createtemporary( p_zipped_blob, true );
    end if;
    dbms_lob.append( p_zipped_blob
                   , utl_raw.concat( hextoraw( '504B0304' ) -- Local file header signature
                                   , hextoraw( '1400' )     -- version 2.0
                                   , hextoraw( '0000' )     -- no General purpose bits
                                   , hextoraw( '0800' )     -- deflate
                                   , little_endian( to_number( to_char( t_now, 'ss' ) ) / 2
                                                  + to_number( to_char( t_now, 'mi' ) ) * 32
                                                  + to_number( to_char( t_now, 'hh24' ) ) * 2048
                                                  , 2
                                                  ) -- File last modification time
                                   , little_endian( to_number( to_char( t_now, 'dd' ) )
                                                  + to_number( to_char( t_now, 'mm' ) ) * 32
                                                  + ( to_number( to_char( t_now, 'yyyy' ) ) - 1980 ) * 512
                                                  , 2
                                                  ) -- File last modification date
                                   , dbms_lob.substr( t_blob, 4, t_clen - 7 )         -- CRC-32
                                   , little_endian( t_clen - 18 )                     -- compressed size
                                   , little_endian( dbms_lob.getlength( p_content ) ) -- uncompressed size
                                   , little_endian( length( p_name ), 2 )             -- File name length
                                   , hextoraw( '0000' )                               -- Extra field length
                                   , utl_raw.cast_to_raw( p_name )                    -- File name
                                   )
                   );
    dbms_lob.copy( p_zipped_blob, t_blob, t_clen - 18, dbms_lob.getlength( p_zipped_blob ) + 1, 11 ); -- compressed content
    dbms_lob.freetemporary( t_blob );
  end;
--
  procedure finish_zip( p_zipped_blob in out blob )
  is
    t_cnt pls_integer := 0;
    t_offs integer;
    t_offs_dir_header integer;
    t_offs_end_header integer;
    t_comment raw(32767) := utl_raw.cast_to_raw( 'Implementation by Anton Scheffer' );
  begin
    t_offs_dir_header := dbms_lob.getlength( p_zipped_blob );
    t_offs := dbms_lob.instr( p_zipped_blob, hextoraw( '504B0304' ), 1 );
    while t_offs > 0
    loop
      t_cnt := t_cnt + 1;
      dbms_lob.append( p_zipped_blob
                     , utl_raw.concat( hextoraw( '504B0102' )      -- Central directory file header signature
                                     , hextoraw( '1400' )          -- version 2.0
                                     , dbms_lob.substr( p_zipped_blob, 26, t_offs + 4 )
                                     , hextoraw( '0000' )          -- File comment length
                                     , hextoraw( '0000' )          -- Disk number where file starts
                                     , hextoraw( '0100' )          -- Internal file attributes
                                     , hextoraw( '2000B681' )      -- External file attributes
                                     , little_endian( t_offs - 1 ) -- Relative offset of local file header
                                     , dbms_lob.substr( p_zipped_blob
                                                      , utl_raw.cast_to_binary_integer( dbms_lob.substr( p_zipped_blob, 2, t_offs + 26 ), utl_raw.little_endian )
                                                      , t_offs + 30
                                                      )            -- File name
                                     )
                     );
      t_offs := dbms_lob.instr( p_zipped_blob, hextoraw( '504B0304' ), t_offs + 32 );
    end loop;
    t_offs_end_header := dbms_lob.getlength( p_zipped_blob );
    dbms_lob.append( p_zipped_blob
                   , utl_raw.concat( hextoraw( '504B0506' )                                    -- End of central directory signature
                                   , hextoraw( '0000' )                                        -- Number of this disk
                                   , hextoraw( '0000' )                                        -- Disk where central directory starts
                                   , little_endian( t_cnt, 2 )                                 -- Number of central directory records on this disk
                                   , little_endian( t_cnt, 2 )                                 -- Total number of central directory records
                                   , little_endian( t_offs_end_header - t_offs_dir_header )    -- Size of central directory
                                   , little_endian( t_offs_dir_header )                        -- Relative offset of local file header
                                   , little_endian( nvl( utl_raw.length( t_comment ), 0 ), 2 ) -- ZIP file comment length
                                   , t_comment
                                   )
                   );
  end;
--
  procedure save_zip
    ( p_zipped_blob blob
    , p_dir varchar2 := 'MY_DIR'
    , p_filename varchar2 := 'my.zip'
    )
  is
    t_fh utl_file.file_type;
    t_len pls_integer := 32767;
  begin
    t_fh := utl_file.fopen( p_dir, p_filename, 'wb' );
    for i in 0 .. trunc( ( dbms_lob.getlength( p_zipped_blob ) - 1 ) / t_len )
    loop
      utl_file.put_raw( t_fh, dbms_lob.substr( p_zipped_blob, t_len, i * t_len + 1 ) );
    end loop;
    utl_file.fclose( t_fh );
  end;
--
end;
/